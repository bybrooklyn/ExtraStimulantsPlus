use std::io;

pub fn io_err(m: &str) -> io::Error {
    io::Error::new(io::ErrorKind::Other, m)
}
