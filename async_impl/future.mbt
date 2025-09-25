/// This file need public visibility because it's used in the public API of async crate.
///

///|
struct FutureReader[T](@primitive.FutureReader[T])

///|
struct FutureWriter[T](@primitive.FutureWriter[T])

///|
struct StreamReader[T](@primitive.StreamReader[T])

///|
struct StreamWriter[T](@primitive.StreamWriter[T])

///|
suberror StreamCancelled (Int, @primitive.Cancelled) derive(Show)

///|
pub async fn[T] FutureReader::read(self : Self[T]) -> T {
  let vtable = self.0.vtable
  let res = (vtable.malloc)(1)
  self.0.update(code=(vtable.read)(self.0.handle, res))
  let _ = @event_loop.perform_job(
    @event_loop.Job::Wait(coro=@coroutine.current_coroutine(), state=self.0),
  )
  for {
    match @primitive.WaitableStatus::from(self.0.code.unwrap()) {
      Blocking | NotSure => @coroutine.suspend()
      Completed(_) => return (vtable.lift)(res)
      Dropped(_) | Cancelled(_) => raise @primitive.Cancelled::Cancelled
    }
  }
}

///|
pub async fn[T] FutureWriter::write(self : Self[T], val : T) -> Unit {
  let vtable = self.0.vtable
  let res = (vtable.malloc)(1)
  (vtable.lower)(val, res)
  self.0.update(code=(vtable.write)(self.0.handle, res))
  let _ = @event_loop.perform_job(
    @event_loop.Job::Wait(coro=@coroutine.current_coroutine(), state=self.0),
  )
  for {
    match @primitive.WaitableStatus::from(self.0.code.unwrap()) {
      Blocking | NotSure => @coroutine.suspend()
      Completed(_) => return
      Dropped(_) | Cancelled(_) => raise @primitive.Cancelled::Cancelled
    }
  }
}

///|
pub async fn[T] StreamReader::read(
  self : StreamReader[T],
  buffer : FixedArray[T],
  offset? : Int = 0,
  length : Int,
) -> Int {
  let buf_ptr = (self.vtable.malloc)(length)
  self.code = Some((self.vtable.read)(self.handle, buf_ptr, length))
  @primitive._async_debug(
    "stream-read(\{self.handle}) -> \{self.code.unwrap()}",
  )
  let _ = @event_loop.perform_job(
    @event_loop.Job::Wait(coro=@coroutine.current_coroutine(), state=self.0),
  )
  for {
    match @primitive.WaitableStatus::from(self.code.unwrap()) {
      Completed(n) => {
        let read_result = (self.vtable.lift)(buf_ptr, n)
        for i in 0..<n {
          buffer[offset + i] = read_result[i]
        }
        return n
      }
      Cancelled(n) | Dropped(n) => {
        let read_result = (self.vtable.lift)(buf_ptr, n)
        for i in 0..<n {
          buffer[offset + i] = read_result[i]
        }
        raise StreamCancelled((n, @primitive.Cancelled::Cancelled))
      }
      Blocking | NotSure => @coroutine.suspend()
    }
  }
}

///|
pub async fn[T] StreamWriter::write(
  self : StreamWriter[T],
  buffer : FixedArray[T],
) -> Int {
  // register this waitable to the current task

  let write_buf = (self.vtable.lower)(buffer)
  self.code = Some((self.vtable.write)(self.handle, write_buf, buffer.length()))
  let _ = @event_loop.perform_job(
    @event_loop.Job::Wait(coro=@coroutine.current_coroutine(), state=self.0),
  )
  for {
    match @primitive.WaitableStatus::from(self.code.unwrap()) {
      Completed(n) => return n
      Cancelled(n) | Dropped(n) =>
        raise StreamCancelled::StreamCancelled(
          (n, @primitive.Cancelled::Cancelled),
        )
      Blocking | NotSure => @coroutine.suspend()
    }
  }
}
