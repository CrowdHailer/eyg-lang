import Workspace from "../../../../../../editor/src/Workspace.svelte"

export function render() {

    let ws = new Workspace({
        target: document.body
    });
    return function (params) {
        ws.$set(params)
    }
}
