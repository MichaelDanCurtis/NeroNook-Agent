(function(root){
  function presentation(state, talk = {}) {
    const voice = {listening:'Listening',thinking:'Thinking',speaking:'Speaking',preparing:'Preparing',permission:'Needs approval'};
    const label = talk.active ? (voice[talk.phase] || 'Starting')
      : state.busy ? 'Working'
      : !state.connected ? 'Connect ChatGPT'
      : state.historyError ? 'History needs attention' : 'Ready';
    return {label, activityLabel: state.presence === 'Needs you'
      ? 'Activity & automations… · Needs review' : 'Activity & automations…'};
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = presentation;
  else root.NeroChatPresence = presentation;
})(globalThis);
