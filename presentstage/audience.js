// The presentation document contains only audience-visible slide content.
const pages = Array.from(document.querySelectorAll('.slide:not([hidden])'));
let active = -1;
function fit() {
    const view = document.querySelector('.view');
    const scale = Math.min(view.clientWidth / 1280, view.clientHeight / 720);
    document.querySelector('.stage').style.setProperty('--scale', scale);
}
addEventListener('resize', fit);
function showSlide(index) {
    if (index < 0 || index >= pages.length || index === active) return;
    if (active >= 0) {
        pages[active].querySelector('video')?.pause();
        pages[active].classList.remove('on');
    }
    active = index;
    const page = pages[index];
    page.classList.add('on');
    const video = page.querySelector('video');
    if (!video) return;
    const film = video.parentElement;
    film.classList.remove('live');
    video.defaultMuted = video.muted = video.autoplay = video.loop = true;
    video.onplaying = () => { if (index === active) film.classList.add('live'); };
    video.onwaiting = video.onstalled = video.onerror = () => film.classList.remove('live');
    if (!video.getAttribute('src')) video.src = video.dataset.media;
    else video.currentTime = 0;
    video.play().catch(() => film.classList.remove('live'));
}
fit();
showSlide(0);
