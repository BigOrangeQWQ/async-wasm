///|
pub struct StreamVTable[T] {
  new : () -> UInt64
  read : (Int, Int, Int) -> Int
  write : (Int, Int, Int) -> Int
  cancel_read : (Int) -> Int
  cancel_write : (Int) -> Int
  drop_readable : (Int) -> Unit
  drop_writable : (Int) -> Unit
  malloc : () -> Int
  free : (Int) -> Unit
  lift : (Int) -> T
  lower : (T, Int) -> Unit
}

///|
pub fn[T] StreamVTable::new(
  new : () -> UInt64,
  read : (Int, Int, Int) -> Int,
  write : (Int, Int, Int) -> Int,
  cancel_read : (Int) -> Int,
  cancel_write : (Int) -> Int,
  drop_readable : (Int) -> Unit,
  drop_writable : (Int) -> Unit,
  malloc : () -> Int,
  free : (Int) -> Unit,
  lift : (Int) -> T,
  lower : (T, Int) -> Unit,
) -> StreamVTable[T] {
  {
    new,
    read,
    write,
    cancel_read,
    cancel_write,
    drop_readable,
    drop_writable,
    malloc,
    free,
    lift,
    lower,
  }
}

pub struct AbiBuffer[T](FixedArray[T])

///|
// pub struct Future[T](Int,FutureVTable[T])
pub struct StreamReader[T] {
  handle : Int
  vtable : StreamVTable[T]
  // code >> 4 : copy result count, code & 0xf : event type
  mut mode : Int? 
}


