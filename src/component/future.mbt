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
pub fn[T] Future::new(handle : Int, vtable : FutureVTable[T]) -> Future[T] {
  Future(handle, vtable)
}

///|
pub fn[T] Future::read(self : Future[T], ptr : Int) -> WaitableStatus {
  WaitableStatus::decode((self.1.read)(self.0, ptr))
}

///|
pub fn[T] Future::write(self : Future[T], ptr : Int) -> WaitableStatus {
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
pub async fn[T] Future::async_write(self : Future[T], value : T) -> Unit raise {
  let buf_ptr = (self.1.malloc)()
  (self.1.lower)(value, buf_ptr)
  // defer (self.1.free)(buf_ptr) TODO: may cause read after free,need check
  let status = self.write(buf_ptr)
  defer (self.1.drop_writable)(self.0)
  match status {
    Completed(_) => return
    Dropped(_) | Cancelled(_) => raise @coroutine.Cancelled
    Blocking => @coroutine.suspend()
  }
  // when receive event, continue this coroutine
  return
}

///|
pub async fn[T] Future::async_read(self : Future[T]) -> T raise {
  let buf_ptr = (self.1.malloc)()
  defer (self.1.free)(buf_ptr)
  let status = self.read(buf_ptr)
  defer self.drop_readable()
  match status {
    Completed(_) => return (self.1.lift)(buf_ptr)
    Dropped(_) | Cancelled(_) => raise @coroutine.Cancelled
    Blocking => @coroutine.suspend()
  }
  // when receive event, continue this coroutine
  return (self.1.lift)(buf_ptr)
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

///|
pub async fn[T] Stream::async_write(self : Stream[T], value : T) -> Unit raise {
  let buf_ptr = (self.1.malloc)()
  (self.1.lower)(value, buf_ptr)
  defer (self.1.free)(buf_ptr)
  let status = self.write(buf_ptr, 1)
  defer (self.1.drop_writable)(self.0)
  match status {
    Blocking => @coroutine.suspend()
    Completed(_) => return
    Dropped(_) | Cancelled(_) => raise @coroutine.Cancelled
  }
  // when receive event, continue this coroutine
  return
}

///|
pub async fn[T] Stream::async_read(self : Stream[T]) -> T? raise {
  let buf_ptr = (self.1.malloc)()
  defer (self.1.free)(buf_ptr)
  let status = self.read(buf_ptr, 1)
  defer ignore(self.drop_readable())
  match status {
    Blocking => @coroutine.suspend()
    Completed(_) => return Some((self.1.lift)(buf_ptr))
    Dropped(_) | Cancelled(_) => raise @coroutine.Cancelled
  }
  // when receive event, continue this coroutine
  return Some((self.1.lift)(buf_ptr))
}
