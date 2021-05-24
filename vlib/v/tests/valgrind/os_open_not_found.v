import os
fn main() {
        mut f := os.open('t.tmp') or {
                eprintln(err)
                return
        }
        f.close()
}
