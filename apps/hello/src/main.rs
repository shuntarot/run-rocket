//! The smallest program: one line on the console, then exit status 0.

#![no_std]
#![no_main]

use rocket_bsp::{entry, exit, println};

#[entry]
fn main() -> ! {
    println!("hello from MiniRocket");
    exit(0)
}
