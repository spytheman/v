module zxyw

import ui

pub struct Foo {
mut:
        parent  ui.Layout
}

pub fn new_foo() &Foo {
        mut bs := &Foo{
//			parent: voidptr(0)
        }
        return bs
        // return &Foo{}
}
