///|
pub struct FutureVTable[T] {
  new : () -> UInt64
  read : (Int, Int) -> Int
  write : (Int, Int) -> Int
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
pub fn[T] FutureVTable::new(
  new : () -> UInt64,
  read : (Int, Int) -> Int,
  write : (Int, Int) -> Int,
  cancel_read : (Int) -> Int,
  cancel_write : (Int) -> Int,
  drop_readable : (Int) -> Unit,
  drop_writable : (Int) -> Unit,
  malloc : () -> Int,
  free : (Int) -> Unit,
  lift : (Int) -> T,
  lower : (T, Int) -> Unit,
) -> FutureVTable[T] {
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

///|
pub struct Future[T](Int,FutureVTable[T])

///|
pub fn[T] Future::new_future(
  vtable : FutureVTable[T],
) -> (Future[T], Future[T]) {
  let handle = (vtable.new)()
  let left_handle = handle.to_int()
  let right_handle = left_handle >> 32
  (Future(left_handle, vtable), Future(right_handle, vtable))
}

///|
pub fn[T] Future::new(handle : Int, vtable : FutureVTable[T]) -> Future[T] {
  Future(handle, vtable)
}

///|
pub fn[T] Future::lower_read(self : Future[T], ptr : Int) -> WaitableStatus {
  WaitableStatus::decode((self.1.read)(self.0, ptr))
}

///|
pub fn[T] Future::lower_write(self : Future[T], ptr : Int) -> WaitableStatus {
  WaitableStatus::decode((self.1.write)(self.0, ptr))
}

///|
pub fn[T] Future::cancel_read(self : Future[T]) -> WaitableStatus {
  WaitableStatus::decode((self.1.cancel_read)(self.0))
}

///|
pub fn[T] Future::cancel_write(self : Future[T]) -> WaitableStatus {
  WaitableStatus::decode((self.1.cancel_write)(self.0))
}

///|
pub fn[T] Future::drop_readable(self : Future[T]) -> Unit {
  (self.1.drop_readable)(self.0)
}

///|
pub fn[T] Future::drop_writable(self : Future[T]) -> Unit {
  (self.1.drop_writable)(self.0)
}

///|
pub fn[T] Future::handle(self : Future[T]) -> Int {
  self.0
}

///|
pub fn[T] Future::vtable(self : Future[T]) -> FutureVTable[T] {
  self.1
}

///|
pub struct FutureReader[T](Future[T])

///|
pub struct FutureWriter[T](Future[T])

///|
pub fn[T] FutureReader::new(future : Future[T]) -> FutureReader[T] {
  FutureReader(future)
}

///|
pub fn[T] FutureWriter::new(future : Future[T]) -> FutureWriter[T] {
  FutureWriter(future)
}

///|
pub async fn[T] FutureReader::read(self : FutureReader[T]) -> T raise {
  self.0.read()
}

///|
pub async fn[T] FutureWriter::write(
  self : FutureWriter[T],
  value : T,
) -> Unit raise {
  self.0.write(value)
}

///|
pub async fn[T] Future::write(self : Future[T], value : T) -> Unit raise {
  let buf_ptr = (self.1.malloc)()
  (self.1.lower)(value, buf_ptr)
  let status = self.lower_write(buf_ptr)
  defer (self.1.free)(buf_ptr)
  match status {
    Completed(_) => return
    Dropped(_) | Cancelled(_) => raise @coroutine.Cancelled
    Blocking => @coroutine.suspend()
  }
  // when receive event, continue this coroutine
  return
}

///|
pub async fn[T] Future::read(self : Future[T]) -> T raise {
  let buf_ptr = (self.1.malloc)()
  let status = self.lower_read(buf_ptr)
  defer (self.1.free)(buf_ptr)
  match status {
    Completed(_) => return (self.1.lift)(buf_ptr)
    Dropped(_) | Cancelled(_) => raise @coroutine.Cancelled
    Blocking => @coroutine.suspend()
  }
  // when receive event, continue this coroutine
  return (self.1.lift)(buf_ptr)
}

pub async fn[T] Future::read_then_drop(self : Future[T]) -> T raise {
  defer self.drop_readable()
  let x = self.read() // defer bug
  return x // self.read()
}

pub async fn[T] Future::write_then_drop(self : Future[T], value : T) -> Unit raise {
  defer self.drop_writable()
  return self.write(value)
}


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

///|
// TODO: stream async read/write
pub struct Stream[T](Int,StreamVTable[T])

///|
pub fn[T] Stream::new(handle : Int, vtable : StreamVTable[T]) -> Stream[T] {
  Stream(handle, vtable)
}

///|
pub fn[T] Stream::read(
  self : Stream[T],
  ptr : Int,
  size : Int,
) -> WaitableStatus {
  WaitableStatus::decode((self.1.read)(self.0, ptr, size))
}

///|
pub fn[T] Stream::write(
  self : Stream[T],
  ptr : Int,
  size : Int,
) -> WaitableStatus {
  WaitableStatus::decode((self.1.write)(self.0, ptr, size))
}

///|
pub fn[T] Stream::cancel_read(self : Stream[T]) -> WaitableStatus {
  WaitableStatus::decode((self.1.cancel_read)(self.0))
}

///|
pub fn[T] Stream::cancel_write(self : Stream[T]) -> WaitableStatus {
  WaitableStatus::decode((self.1.cancel_write)(self.0))
}

///|
pub fn[T] Stream::drop_readable(self : Stream[T]) -> Unit {
  (self.1.drop_readable)(self.0)
}

///|
pub fn[T] Stream::drop_writable(self : Stream[T]) -> Unit {
  (self.1.drop_writable)(self.0)
}

///|
pub fn[T] Stream::handle(self : Stream[T]) -> Int {
  self.0
}

///|
pub fn[T] Stream::vtable(self : Stream[T]) -> StreamVTable[T] {
  self.1
}
