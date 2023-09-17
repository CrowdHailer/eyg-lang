import * as readline from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';

export function createInterface(completer) {
    return readline.createInterface({ input, output, completer });
}

export function question(rl, prompt) {
    return rl.question(prompt)
}

export function close(rl) {
    return rl.close()
}
