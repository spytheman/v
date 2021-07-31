module zxyw

import ui

pub struct Bar {
mut:
        parent  ui.Layout
}

pub fn new_bar() &Bar {
        mut bs := &Bar{
                // parent: voidptr(0)
        }
        return bs
}    
