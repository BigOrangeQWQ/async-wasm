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
  evloop.run_forever()
  main.unwrap()
}

pub fn yield_async(id: Int) -> Unit {
  guard curr_loop.val is Some(evloop)
  guard evloop.0.get(id) is Some(coro) else {
  }
  coro.run()
}

pub fn spawn_async(id: Int, coro: @coroutine.Coroutine) -> Unit {
  guard curr_loop.val is Some(evloop)
  evloop.0[id] = coro
  coro.wake()
}


///|
fn EventLoop::run_forever(self : Self) -> Unit {
  while !@coroutine.no_more_work() {
    @coroutine.rschedule()
  }
  self.0.clear()
}

// 这里调度 Async 提案的轮询

pub enum LoopCoroutineId {
  MoonBit = 1
  SubTask = 2
  Coroutine = 3
  Stream = 4
}