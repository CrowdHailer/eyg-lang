// Only task operations are exposed to EYG; registry bootstrap stays host-owned.
export { define, list, get, result, cancel, forget, run, resetSlots } from './background-bootstrap';
