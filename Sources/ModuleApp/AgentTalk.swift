import AppKit
import Combine
import Foundation
import ModuleCore
import NookPluginSDK

@MainActor final class AgentTalk: ObservableObject {
    let client = PluginSpeechConversationClient()
    let expression = PluginExpressionPlayback()
    private var replyCue: PluginExpressionCue?
    private(set) var expressionEnabled = false
    func chooseExpression(_ enabled: Bool) throws {
        guard active,client.ready else { throw AgentError.message("Start Talk before enabling expressive delivery.") }
        expressionEnabled=enabled; if !enabled { expression.clear() }; changed?()
    }
    @Published var mode = UserDefaults.standard.string(forKey:"talkDuplex") ?? "half"
    @Published var quickReplies = UserDefaults.standard.object(forKey:"talkQuickReplies") as? Bool ?? true
    @Published var phase = "idle"
    @Published var partial = ""
    @Published var status = "Press Talk to start"
    @Published var level = 0.0
    @Published var outputLevel = 0.0
    var recoveryDraft = ""
    var changed:(()->Void)?
    var available:()->Bool = {false}
    private weak var model:AgentModel?
    private var request:UUID?,turn=0
    private var queue=ConversationSpeechQueue(),playing=false,chunk="",heard=""
    private var useContext=false
    private var observations:[NSObjectProtocol]=[]
    private var clientObservation:AnyCancellable?
    init(){
        expression.changed = { [weak self] in self?.changed?() }
        client.event={ [weak self] in self?.receive($0) }
        client.ended={ [weak self] in self?.retired() }
        clientObservation=client.objectWillChange.sink{[weak self] _ in Task{@MainActor in self?.changed?()}}
        for name in [NSWorkspace.willSleepNotification,NSWorkspace.sessionDidResignActiveNotification]{observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName:name,object:nil,queue:.main){[weak self] _ in Task{@MainActor in self?.stop()}})}
    }
    func bind(_ model:AgentModel){self.model=model;model.voiceDelivery = { [weak self] id,cue in guard let self, self.request == id else { return }; self.replyCue = cue };model.voiceReply={ [weak self] id,text,final,success,sealed in self?.reply(id,text:text,final:final,success:success,sealed:sealed) }}
    var active:Bool{client.active}
    func chooseReplyPace(_ value:String) throws {
        guard ["quick","default"].contains(value) else{throw AgentError.message("Choose a reply pace")}
        quickReplies=value=="quick";UserDefaults.standard.set(quickReplies,forKey:"talkQuickReplies");changed?()
    }
    func start(context:Bool) throws {
        guard available(),let model,!model.busy,model.email != nil else{throw AgentError.message("Connect the agent and finish the current reply before Talk.")}
        try AgentModelChoice.validate(model.selectedModel, choices:model.models)
        useContext=context;recoveryDraft="";turn=0;partial="";phase="preparing";status="Starting local speech…"
        try client.start(mode:mode);changed?()
    }
    func chooseMode(_ value:String) throws {
        let next=try PluginSpeechConversation.mode(value)
        if client.ready{try client.input(PluginSpeechConversation.values("mode",mode:next))}
        else{mode=next;UserDefaults.standard.set(next,forKey:"talkDuplex")};changed?()
    }
    func sendText(_ text:String) throws {
        guard active,client.ready else {throw AgentError.message("Wait for local speech to be ready.")}
        try client.input(PluginSpeechConversation.values("text",text:text,turn:turn))
    }
    func stop(){interrupt();client.stop();phase="idle";partial="";level=0;outputLevel=0;status="Conversation stopped";changed?()}
    private func retired(){
        if let request{model?.markVoice(request,heard:heard,interrupted:true);model?.cancel(request:request)}
        expression.clear();expressionEnabled=false;replyCue=nil;request=nil;playing=false;queue=ConversationSpeechQueue();phase="idle";partial="";level=0;outputLevel=0;changed?()
    }
    private func interrupt(notifyProvider:Bool=true){
        outputLevel=0;expression.clear();replyCue=nil
        let old=request;request=nil
        if let old{model?.markVoice(old,heard:heard,interrupted:true);model?.cancel(request:old)}
        queue=ConversationSpeechQueue();playing=false;chunk=""
        if notifyProvider && client.ready{try? client.input(PluginSpeechConversation.values("interrupt",turn:turn))}
    }
    private func receive(_ values:[String:PluginValue]){
        guard case .string(let kind)=values["kind"] else{return}
        func text(_ key:String)->String{if case .string(let x)=values[key]{return x};return ""}
        switch kind {
        case "ready","listening":
            if ["full","half"].contains(text("mode")){mode=text("mode");UserDefaults.standard.set(mode,forKey:"talkDuplex")}
            phase="listening";status=text("text").isEmpty ? "Listening" : text("text");partial=""
        case "mode":let next=text("mode");if ["full","half"].contains(next){mode=next;UserDefaults.standard.set(next,forKey:"talkDuplex")};if !text("text").isEmpty{status=text("text")}
        case "meter":if case .number(let x)=values["level"]{level=x};if phase=="listening",!text("text").isEmpty{status=text("text")}
        case "playbackMeter":
            if case .number(let n)=values["turn"],n==Double(turn),phase=="speaking",case .number(let x)=values["level"] { outputLevel=PluginAvatarSpeech.weight(x,speaking:true) } else { outputLevel=0 }
        case "partial":partial=text("text")
        case "speechStarted":interrupt(notifyProvider:false);phase="listening";status="Listening"
        case "final":
            guard case .number(let n)=values["turn"],n.rounded()==n,n>Double(turn),let model else{return}
            expression.clear();replyCue=nil;turn=Int(n);SpeechTiming.mark("recognized",turn:turn);partial="";heard="";queue=ConversationSpeechQueue();playing=false
            request=model.sendVoice(text("text"),useContext:useContext,quick:quickReplies)
            if request==nil{stop();status="Agent is reconnecting. Your words are saved below; try again when connected.";recoveryDraft=text("text")}
            else{phase="thinking";status="Thinking"}
        case "expressionStarted": _ = expression.started(text("text"))
        case "speaking":
            guard playing,case .number(let n)=values["turn"],n==Double(turn) else{return};phase="speaking";status="Speaking"
        case "played":
            guard case .number(let n)=values["turn"],Int(n)==turn,playing else{return}
            outputLevel=0;expression.clear()
            heard += (heard.isEmpty ? "":" ")+chunk;if let request{model?.markVoice(request,heard:heard)};playing=false;chunk="";advance()
        default:break
        };changed?()
    }
    private func reply(_ id:UUID,text:String,final:Bool,success:Bool,sealed:Bool){
        guard active,request==id else{return}
        if final && !success{interrupt();try? client.input(PluginSpeechConversation.values("listen",turn:turn));phase="listening";status="Reply stopped · listening";return}
        do{try queue.append(text,final:final,sealed:sealed);advance()}catch{stop();status=error.localizedDescription};changed?()
    }
    private func advance(){
        guard active,client.ready,!playing else{return}
        if let next=queue.next(){
            do{SpeechTiming.mark("chunkSent",turn:turn);chunk=next;playing=true;expression.stage(try client.speak(next,cue:expressionEnabled ? replyCue:nil,turn:turn));phase="preparing";status="Preparing speech…"}
            catch{stop();status=error.localizedDescription}
        }else if queue.drained{
            if let request{model?.markVoice(request,heard:heard)};request=nil
            do{try client.input(PluginSpeechConversation.values("listen",turn:turn));phase="listening";status="Listening"}catch{stop();status=error.localizedDescription}
        }
        changed?()
    }
}
