// stdin: keys<TAB>... per message. stdout: what Gõ Nhanh produces (Telex, English auto-restore unless --no-restore).
use gonhanh_core::engine::Engine;
use gonhanh_core::utils::type_word;
use std::io::{BufRead, Write};
fn main() {
    let restore = !std::env::args().any(|x| x == "--no-restore");
    let out = std::io::stdout(); let mut out = out.lock();
    for l in std::io::stdin().lock().lines() {
        let l = l.unwrap(); let keys = l.split('\t').next().unwrap();
        let mut e = Engine::new(); e.set_english_auto_restore(restore);
        let s = type_word(&mut e, &format!("{} ", keys));
        writeln!(out, "{}", s.trim_end()).unwrap();
    }
}
