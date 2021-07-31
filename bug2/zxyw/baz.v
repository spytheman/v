module zxyw

import ui

pub struct Baz {
mut:
        parent ui.Layout
}

pub fn new_baz() &Baz {
        mut cd := &Baz{
                // parent: voidptr(0)
        }
        return cd
}
