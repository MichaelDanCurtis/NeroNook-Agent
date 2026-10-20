import Foundation
import ModuleCore

/// Authored, text-only comparison against the existing isolated account runtime.
/// The frozen and new queues consume the SAME streamed response. No microphone,
/// tools, user chats, external credentials or history writes are involved.
@MainActor enum SpeechLatencyCheck {
    static func run(binary: URL, compareEffort: Bool = false) async throws {
        let directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("NeroNook-Plugins/cafe.nero.plugin.agent/codex-runtime")
        let client=CodexClient(directory:directory);defer{client.stop()}
        try await client.start(binary:binary)
        let account=try await client.request("account/read",["refreshToken":false])
        guard (account["account"] as? [String:Any])?["type"] as? String == "chatgpt" else {throw AgentError.message("Existing managed sign-in is unavailable")}
        let models=try await client.request("model/list",[:])
        let catalog=models["data"] as? [[String:Any]] ?? []
        var rows:[[String:Any]]=[]
        for sample in 0..<(compareEffort ? 6:3) {
            let pair=sample/2
            let low=compareEffort && (pair.isMultiple(of:2) ? sample.isMultiple(of:2) : !sample.isMultiple(of:2))
            let question=compareEffort && pair==1 ? "What is 17 times 23? Answer in one short sentence." : "What is the capital of Spain? Answer in one short sentence."
            let expected=compareEffort && pair==1 ? "391":"madrid"
            let start=ProcessInfo.processInfo.systemUptime
            let result=try await client.request("thread/start",["cwd":directory.appendingPathComponent("workspace").path,"ephemeral":true,"sandbox":"read-only","approvalPolicy":"never","config":["web_search":"disabled"],"baseInstructions":AgentConversationInstructions.make(nook:false,web:false,integrations:[])])
            let threadSeconds=ProcessInfo.processInfo.systemUptime-start
            guard let id=(result["thread"] as? [String:Any])?["id"] as? String else {throw AgentError.message("No diagnostic thread")}
            let model=result["model"] as? String ?? ""
            let entry=catalog.first{($0["model"] as? String ?? $0["id"] as? String)==model}
            let supported=(entry?["supportedReasoningEfforts"] as? [[String:Any]] ?? []).compactMap{$0["reasoningEffort"] as? String}
            if low && !supported.contains("low") {throw AgentError.message("Selected model does not advertise low effort")}
            let (events,continuation)=AsyncStream<String>.makeStream(bufferingPolicy:.bufferingNewest(1))
            var raw="",old=BaselineSpeechQueue(),new=ConversationSpeechQueue()
            var firstReply:Double?,firstOld:Double?,firstNew:Double?,sealedAt:Double?
            var failure=false
            func readQueues(_ final:Bool) {
                let preview=AgentAnswer.streamingReply(raw),at=ProcessInfo.processInfo.systemUptime-start
                if firstReply==nil,!preview.text.isEmpty {firstReply=at}
                if sealedAt==nil,preview.sealed {sealedAt=at}
                do {
                    try old.append(preview.text,final:final);try new.append(preview.text,final:final,sealed:preview.sealed)
                    while let _=old.next() {if firstOld==nil {firstOld=at}}
                    while let _=new.next() {if firstNew==nil {firstNew=at}}
                }catch{failure=true}
            }
            client.event={method,params in
                guard params["threadId"] as? String == id else{return}
                if method == "item/agentMessage/delta",let delta=params["delta"] as? String {
                    guard raw.utf8.count+delta.utf8.count<=65536 else {failure=true;continuation.finish();return}
                    raw+=delta;readQueues(false)
                }
                if method == "item/completed",let item=params["item"] as? [String:Any],item["type"] as? String == "agentMessage",let text=item["text"] as? String,text.utf8.count<=65536 {raw=text;readQueues(false)}
                if method == "turn/completed",let turn=params["turn"] as? [String:Any] {
                    readQueues(true);continuation.yield(turn["status"] as? String ?? "unknown");continuation.finish()
                }
            }
            var parameters:[String:Any]=["threadId":id,"input":[["type":"text","text":question]],"sandboxPolicy":["type":"readOnly","networkAccess":false],"approvalPolicy":"never","outputSchema":AgentAnswer.schema]
            if low {parameters["effort"]="low"}
            _=try await client.request("turn/start",parameters)
            let timeout=Task{try? await Task.sleep(for:.seconds(45));if !Task.isCancelled{continuation.finish()}}
            var iterator=events.makeAsyncIterator();let status=await iterator.next();timeout.cancel()
            let finished=ProcessInfo.processInfo.systemUptime-start
            guard status == "completed",!failure,let firstOld,let firstNew,let answer=try? JSONDecoder().decode(AgentAnswer.self,from:Data(raw.utf8)),answer.action==nil,answer.reply.lowercased().contains(expected) else {throw AgentError.message("Authored spoken-reply comparison did not complete correctly")}
            rows.append(["sample":sample,"pair":pair,"effort":low ? "low":"model default","supportedEfforts":supported,"model":model,"threadSeconds":threadSeconds,"firstTextSeconds":firstReply ?? -1,"replySealedSeconds":sealedAt ?? -1,"baselineChunkSeconds":firstOld,"newChunkSeconds":firstNew,"completedSeconds":finished,"replyValidated":true])
        }
        let receipt:[String:Any]=["scope":compareEffort ? "Six authored requests in three interleaved low/default effort pairs; selected model unchanged; existing isolated account; no tools or capture":"Three authored text-only requests; same response stream for both queues; existing isolated managed account; no tools or capture","rows":rows]
        print(String(decoding:try JSONSerialization.data(withJSONObject:receipt,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
