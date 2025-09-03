// 这里应该是 BLOCK ON 的原语

///|
priv struct EventLoop(Map[Int, @coroutine.Coroutine])

///|
let curr_loop : Ref[EventLoop?] = @ref.new(None)

///|
pub fn with_event_loop(f : async () -> Unit raise) -> Unit raise {
  guard curr_loop.val is None
  let evloop : EventLoop = {}
  curr_loop.val = Some(evloop)
  defer {
    curr_loop.val = None
  }
  let main = @coroutine.spawn(f)
  @coroutine.rschedule()
  evloop.run_forever()
  main.unwrap()
}

///|
pub fn yield_async(id : Int) -> Unit {
  guard curr_loop.val is Some(evloop)
  guard evloop.0.get(id) is Some(coro) else {  }
  coro.run()
}

///|
/// TODO: this function may not be necessary
pub fn spawn_async(id : Int, coro : @coroutine.Coroutine) -> Unit {
  guard curr_loop.val is Some(evloop)
  evloop.0[id] = coro
  coro.wake()
}

///|
/// It may be replaced by callback block_on
fn EventLoop::run_forever(self : Self) -> Unit {
  while !@coroutine.no_more_work() {
    @coroutine.rschedule()
  }
  self.0.clear()
}
