const params = new URLSearchParams(location.search);
const speakerMode = params.get('view') === 'transcript';
const session = params.get('session') || 'default';
const storagePrefix = 'presentstage:' + location.pathname + ':';
const sessionKey = storagePrefix + 'session:' + session;
const notes = JSON.parse(document.getElementById('speaker-notes').textContent);
const byId = id => document.getElementById(id);
const editor = byId('words');
let state = {page: 0, start: null};
let displayed = -1;

function readState() {
    return JSON.parse(localStorage.getItem(sessionKey)) || state;
}
function noteKey(index) {
    return storagePrefix + 'note:' + index + ':' + notes[index].title;
}
function updateClock() {
    const seconds = state.start ? Math.max(0, Math.floor((Date.now() - state.start) / 1000)) : 0;
    byId('clock').textContent = Math.floor(seconds / 60) + ':' + String(seconds % 60).padStart(2, '0');
}
function render() {
    state = readState();
    if (speakerMode) updateClock();
    const index = Math.min(Math.max(0, state.page), notes.length - 1);
    if (displayed === index) return;
    displayed = index;
    showSlide(index);
    if (!speakerMode) return;
    const note = notes[index];
    byId('position').textContent = [`Slide ${index + 1} / ${notes.length}`, note.time].filter(Boolean).join(' · ');
    byId('heading').textContent = note.title;
    editor.value = localStorage.getItem(noteKey(index)) ?? note.text;
    editor.scrollTop = 0;
}
function publish(next) {
    localStorage.setItem(sessionKey, JSON.stringify(next));
    render();
}
function move(step) {
    const current = readState();
    if (step > 0 && current.page === 0 && current.start === null) {
        publish({page: 0, start: Date.now()});
        return;
    }
    publish({...current, page: Math.min(notes.length - 1, Math.max(0, current.page + step))});
}

addEventListener('storage', event => { if (event.key === sessionKey) render(); });
addEventListener('keydown', event => {
    if (event.isComposing || event.metaKey || event.altKey || event.ctrlKey) return;
    if (event.target === editor) {
        if (event.key === 'Escape') editor.blur();
        return;
    }
    if (event.target.tagName === 'BUTTON' || event.repeat) return;
    switch (event.key) {
    case 'ArrowRight': case 'PageDown': case ' ': event.preventDefault(); move(1); break;
    case 'ArrowLeft': case 'PageUp': event.preventDefault(); move(-1); break;
    case 'f':
        if (document.fullscreenElement) document.exitFullscreen();
        else document.documentElement.requestFullscreen();
        break;
    case 'p': {
        const url = new URL(location.href);
        url.searchParams.set('view', speakerMode ? 'slides' : 'transcript');
        window.open(url, 'presentstage-' + url.searchParams.get('view') + '-' + session, 'popup');
        break;
    }
    }
});
addEventListener('contextmenu', event => {
    if (event.target === editor) return;
    event.preventDefault();
    move(1);
});
if (speakerMode) {
    byId('preview').append(document.querySelector('.view'));
    byId('speaker').hidden = false;
    fit();
    editor.oninput = () => localStorage.setItem(noteKey(displayed), editor.value);
    byId('back').onclick = () => move(-1);
    byId('forward').onclick = () => move(1);
    byId('reset').onclick = () => {
        const current = readState();
        publish({...current, start: current.page === 0 ? null : Date.now()});
    };
    setInterval(updateClock, 250);
}
render();
