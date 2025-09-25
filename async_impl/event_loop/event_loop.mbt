///|
pub(all) enum Job {
  Wait(coro~ : @coroutine.Coroutine, state~ : &@primitive.Waitable)
  Coroutine(@coroutine.Coroutine)
}

///|
priv struct EventLoop {
  mut coro : @coroutine.Coroutine?
  set : @primitive.WaitableSet
  jobs : Map[Int, @coroutine.Coroutine]
  comp : Map[Int, ComponentHandle]
  deque : @deque.Deque[Int] // free handles
}

///|
priv struct ComponentHandle {
  handle : Int
  state : &@primitive.Waitable
  coro : @coroutine.Coroutine
}

///|
fn ComponentHandle::new(
  handle : Int,
  state : &@primitive.Waitable,
  coro : @coroutine.Coroutine,
) -> ComponentHandle {
  { handle, state, coro }
}

///|
let evloop_map : Map[Int, EventLoop] = {}

///|
priv struct EventLoopHook {
  init : (() -> Unit)?
  exit : (() -> Unit)?
}

///|
let hooks : Array[EventLoopHook] = []

///|
pub fn register_hook(init? : () -> Unit, exit? : () -> Unit) -> Unit {
  hooks.push({ init, exit })
}

///|
fn EventLoop::no_more_work(self : Self) -> Bool {
  self.jobs.is_empty() && self.comp.is_empty()
}

///|
fn current_loop() -> EventLoop {
  let set = @primitive.context_get()
  guard set != 0
  evloop_map[set]
}

///|
async fn poll(
  event : @primitive.Event,
  waitable : Int,
  status : Int,
) -> (@primitive.CallbackCode, Bool) {
  let evloop = current_loop()
  match event {
    @primitive.Event::None => {
      if waitable != 0 || status != 0 {
        panic() // unreachable
      }
      (@primitive.CallbackCode::Exit, false)
    }
    TaskCancel => {
      evloop.comp
      .iter()
      .each(fn(comp) {
        let (_, comp) = comp
        @coroutine.coroutine_cancel(comp.coro)
        comp.state.cancel()
      })
      if evloop.coro is Some(coro) {
        @coroutine.coroutine_wake(coro) // wake main loop
      }
      raise @primitive.Cancelled::Cancelled
    }
    FutureRead | FutureWrite | StreamRead | StreamWrite | Subtask => {
      let task = evloop.comp[waitable]
      let state = task.state
      state.update(code=status)
      if state.done() {
        // remove waitable from set
        evloop.set.remove_waitable(waitable)
        // drop waitable
        if state.ty() is Subtask {
          ignore(state.drop())
        }
        // remove from tracking
        evloop.comp.remove(waitable)
      }
      if evloop.no_more_work() && evloop.coro is Some(coro) {
        @coroutine.coroutine_wake(coro) // wake main loop
        @coroutine.pause()
        return (@primitive.CallbackCode::Exit, true)
      }
      (@primitive.CallbackCode::Wait(evloop.set.0), false)
    }
  }
}

///|
fn EventLoop::run_forever(self : Self) -> Unit raise {
  let poll = @coroutine.spawn(fn() {
    let mut event = (0, 0, 0)
    for {
      if self.no_more_work() {
        break
      }
      let code = poll(@primitive.Event::from(event.0), event.1, event.2)
      match code {
        (@primitive.CallbackCode::Exit, true) => break
        _ => event = self.set.wait()
      }
    }
  })
  self.coro = Some(poll)
  @coroutine.reschedule()
  @coroutine.coroutine_unwrap(poll)
}

///|
pub fn with_event_loop(f : async () -> Unit) -> Unit raise {
  let evloop = {
    set: @primitive.WaitableSet::new(),
    coro: None,
    jobs: {},
    comp: {},
    deque: @deque.Deque::new(),
  }
  evloop_map[evloop.set.0] = evloop
  for hook in hooks {
    guard hook.init is Some(init)
    init()
  }
  try {
    defer {
      let evloop = current_loop()
      while evloop.deque.pop_back() is Some(handle) {
        let comp = evloop.comp[handle]
        let _ = comp.state.drop()
        evloop.comp.remove(handle)
      }
      evloop_map.remove(evloop.set.0)
      @primitive.context_set(0)
      evloop.set.drop()
    }
    let main = @coroutine.spawn(f)
    evloop.run_forever()
    @coroutine.coroutine_unwrap(main)
  } catch {
    err => {
      for hook in hooks {
        guard hook.exit is Some(exit)
        exit()
      }
      raise err
    }
  }
}

// return waitable handle

///|
pub async fn perform_job(job : Job) -> Int {
  match job {
    Wait(coro~, state~) => {
      let evloop = current_loop()
      let handle = state.handle()
      evloop.comp[handle] = ComponentHandle::new(handle, state, coro)
      handle
    }
    Coroutine(coro) => {
      let evloop = current_loop()
      let id = evloop.jobs.size() + 1
      evloop.jobs[id] = coro
      id
    }
  }
}
