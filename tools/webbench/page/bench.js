// Page controller: mounts the requested field, sets the title contract, and POSTs
// what the page saw 800 ms after the last input.
//   title: webbench-<token>-ready once mounted, webbench-<token>-error on a load error.
//   POST /result: {token, case, field, text, inputs} where inputs are epoch ms.

const DEBOUNCE_MS = 800;
const params = new URLSearchParams(location.search);
const field = params.get('field') || '';
const token = params.get('token') || '';
const caseParam = params.get('case') || '';
const TOKEN_OK = /^[A-Za-z0-9_-]{1,64}$/.test(token);
const CASE_OK = /^[0-9]{1,6}$/.test(caseParam);

const inputs = [];
let handle = null;
let timer = null;

function setTitle(state) {
  document.title = TOKEN_OK ? `webbench-${token}-${state}` : 'webbench-error';
}

function onChange() {
  inputs.push(performance.timeOrigin + performance.now());
  clearTimeout(timer);
  timer = setTimeout(post, DEBOUNCE_MS);
}

async function post() {
  if (!handle) return;
  const body = {
    token,
    case: Number(caseParam),
    field,
    text: handle.getText(),
    inputs: inputs.slice(),
  };
  try {
    await fetch('/result', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  } catch (err) {
    console.error('webbench post failed', err);
  }
}

async function main() {
  if (!TOKEN_OK || !CASE_OK) {
    setTitle('error');
    return;
  }
  try {
    const { FIELDS } = await import('./fields.js');
    const mount = FIELDS[field];
    if (!mount) throw new Error(`unknown field: ${field}`);
    handle = await mount(document.getElementById('stage'), onChange, () => setTitle('error'));
    handle.focus();
    setTitle('ready');
  } catch (err) {
    console.error(err);
    setTitle('error');
  }
}

main();
