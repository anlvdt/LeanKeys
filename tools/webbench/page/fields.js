// One factory per field kind. Each mounts a minimal, plain-text editor into `stage`,
// calls onChange() on every user edit, and returns { getText, focus }.
// Libraries load inside their own factory, so one CDN failure only breaks its field.

const SUGGESTIONS = ['https://www.facebook.com/messages', 'https://tiki.vn', 'https://vnexpress.net'];

function setCommon(el) {
  el.classList.add('field');
  el.setAttribute('autocomplete', 'off');
  el.setAttribute('autocapitalize', 'off');
  el.setAttribute('spellcheck', 'false');
}

function caretToEnd(el) {
  el.focus();
  const range = document.createRange();
  range.selectNodeContents(el);
  range.collapse(false);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
}

function mountInput(stage, onChange) {
  const el = document.createElement('input');
  el.type = 'text';
  setCommon(el);
  el.addEventListener('input', () => onChange());
  stage.append(el);
  return {
    getText: () => el.value,
    focus: () => {
      el.focus();
      el.setSelectionRange(el.value.length, el.value.length);
    },
  };
}

function mountTextarea(stage, onChange) {
  const el = document.createElement('textarea');
  setCommon(el);
  el.addEventListener('input', () => onChange());
  stage.append(el);
  return {
    getText: () => el.value,
    focus: () => {
      el.focus();
      el.setSelectionRange(el.value.length, el.value.length);
    },
  };
}

function mountContenteditable(stage, onChange) {
  const el = document.createElement('div');
  el.contentEditable = 'true';
  el.setAttribute('role', 'textbox');
  setCommon(el);
  el.addEventListener('input', () => onChange());
  stage.append(el);
  return {
    getText: () => el.innerText,
    focus: () => caretToEnd(el),
  };
}

// Address-bar style completion: after an insertion, append the rest of the first
// matching suggestion and select it, so the next keystroke replaces the selection.
function mountAutocomplete(stage, onChange) {
  const el = document.createElement('input');
  el.type = 'text';
  setCommon(el);
  el.addEventListener('input', (event) => {
    onChange();
    if (event.isComposing || !event.inputType || !event.inputType.startsWith('insert')) return;
    const typed = el.value;
    if (!typed) return;
    const lower = typed.toLowerCase();
    const match = SUGGESTIONS.find((s) => s.toLowerCase().startsWith(lower) && s.length > typed.length);
    if (!match) return;
    el.value = typed + match.slice(typed.length);
    el.setSelectionRange(typed.length, match.length);
  });
  stage.append(el);
  return {
    getText: () => el.value,
    focus: () => {
      el.focus();
      el.setSelectionRange(el.value.length, el.value.length);
    },
  };
}

async function mountLexical(stage, onChange) {
  const [{ createEditor, $getRoot, $createParagraphNode }, { registerPlainText }] = await Promise.all([
    import('lexical'),
    import('@lexical/plain-text'),
  ]);
  const root = document.createElement('div');
  root.contentEditable = 'true';
  setCommon(root);
  stage.append(root);

  const editor = createEditor({
    namespace: 'webbench',
    onError: (error) => { throw error; },
  });
  editor.setRootElement(root);
  registerPlainText(editor);

  let armed = false;
  editor.registerUpdateListener(({ dirtyLeaves, dirtyElements }) => {
    if (armed && (dirtyLeaves.size > 0 || dirtyElements.size > 0)) onChange();
  });
  editor.update(() => {
    $getRoot().append($createParagraphNode());
  }, { discrete: true });
  editor.update(() => {
    $getRoot().selectEnd();
  }, { discrete: true });
  armed = true;

  return {
    getText: () => editor.getEditorState().read(() => $getRoot().getTextContent()),
    focus: () => {
      root.focus();
      editor.update(() => {
        $getRoot().selectEnd();
      }, { discrete: true });
    },
  };
}

async function mountSlate(stage, onChange) {
  const React = (await import('react')).default;
  const { flushSync } = await import('react-dom');
  const { createRoot } = await import('react-dom/client');
  const { createEditor, Editor, Node, Transforms } = await import('slate');
  const { Slate, Editable, withReact, ReactEditor } = await import('slate-react');

  const editor = withReact(createEditor());
  const initialValue = [{ type: 'paragraph', children: [{ text: '' }] }];
  let armed = false;

  const SlateField = () => React.createElement(
    Slate,
    {
      editor,
      initialValue,
      onChange: () => {
        if (armed && editor.operations.some((op) => op.type !== 'set_selection')) onChange();
      },
    },
    React.createElement(Editable, { className: 'field', spellCheck: false }),
  );

  const host = document.createElement('div');
  stage.append(host);
  flushSync(() => {
    createRoot(host).render(React.createElement(SlateField));
  });
  armed = true;

  return {
    getText: () => Node.string(editor),
    focus: () => {
      ReactEditor.focus(editor);
      Transforms.select(editor, Editor.end(editor, []));
    },
  };
}

async function mountProseMirror(stage, onChange) {
  const { EditorState, TextSelection } = await import('prosemirror-state');
  const { EditorView } = await import('prosemirror-view');
  const { schema } = await import('prosemirror-schema-basic');

  let armed = false;
  const view = new EditorView(stage, {
    state: EditorState.create({ doc: schema.topNodeType.createAndFill() }),
    dispatchTransaction(tr) {
      view.updateState(view.state.apply(tr));
      if (armed && tr.docChanged) onChange();
    },
  });
  view.dom.classList.add('field');
  view.dom.setAttribute('spellcheck', 'false');
  armed = true;

  return {
    getText: () => view.state.doc.textContent,
    focus: () => {
      view.focus();
      view.dispatch(view.state.tr.setSelection(TextSelection.atEnd(view.state.doc)));
    },
  };
}

async function mountQuill(stage, onChange) {
  const { default: Quill } = await import('quill');
  const host = document.createElement('div');
  stage.append(host);
  const quill = new Quill(host, { theme: 'snow', modules: { toolbar: false } });
  setCommon(quill.root);
  quill.on('text-change', (_delta, _old, source) => {
    if (source === 'user') onChange();
  });
  return {
    // Quill always keeps a trailing newline; drop it so the text matches the other editors.
    getText: () => quill.getText().replace(/\n$/, ''),
    focus: () => {
      quill.focus();
      quill.setSelection(Math.max(0, quill.getLength() - 1), 0, 'silent');
    },
  };
}

export const FIELDS = {
  input: mountInput,
  textarea: mountTextarea,
  contenteditable: mountContenteditable,
  autocomplete: mountAutocomplete,
  lexical: mountLexical,
  slate: mountSlate,
  prosemirror: mountProseMirror,
  quill: mountQuill,
};
