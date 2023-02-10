export function getHash() {
    return decodeURIComponent(window.location.hash.slice(1))
}

export function setHash(hash) {
    history.replaceState(undefined, undefined, "#" + hash)
}
