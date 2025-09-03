///|
pub struct WaitableTask {
  id : Int
  waitable_set : WaitableSet
  tasks : Map[Int, @coroutine.Coroutine]
} // TaskGroup

///|
pub let task_map : Map[Int, WaitableTask] = {}

///|
pub fn WaitableTask::new() -> WaitableTask {
  let waitable_set = WaitableSet::new()
  set_active_task_context(waitable_set.0)
  { id: waitable_set.0, waitable_set, tasks: {} }
}

///|
pub fn WaitableTask::add_waitable(self : Self, waitable : Int) -> Unit {
  self.waitable_set.join(waitable)
}

///|
pub fn WaitableTask::wait(self : Self) -> (Int, Int, Int) {
  self.waitable_set.wait()
}

///|
pub fn WaitableTask::remove_waitable(self : Self, waitable : Int) -> Unit {
  WaitableSet::remove_waitable_from_all_sets(waitable)
  self.tasks.remove(waitable)
}

///|
pub fn WaitableTask::drop(self : Self) -> Unit {
  set_active_task_context(0) // clear current context
  waitable_set_drop(self.waitable_set.0)
  self.tasks.clear()
}

///|
/// TODO: it may be need WaitableTask::spawn_no_wait
pub fn WaitableTask::spawn(
  task : Self,
  f : async () -> Unit raise,
  waitable : Int,
) -> Unit {
  let coro = @coroutine.spawn(fn() {
    task.add_waitable(waitable)
    defer task.remove_waitable(waitable)
    f()
  })
  task.tasks[waitable] = coro
}

///|
pub fn WaitableTask::spawn_subtask(
  task : Self,
  f : async () -> Unit raise,
  waitable : Int,
) -> Unit {
  let coro = @coroutine.spawn(fn() {
    task.add_waitable(waitable)
    defer task.remove_waitable(waitable)
    defer subtask_drop(waitable)
    f()
  })
  task.tasks[waitable] = coro
}

///|
/// This function is core of the wasm async runtime
/// It is called by the host when an event happens
pub fn callback(event : Int, waitable_id : Int, code : Int) -> Int {
  // EVENT NONE & waitable_id == 0 means just run all ready coroutines
  if event == 0 && waitable_id == 0 && code == 0 {
    @coroutine.rschedule()
    return CallbackCode::Exit.encode()
  }
  // Handle the event for the current waitable task
  guard current_waitable_set() is Some(task)
  let waitable = task.tasks[waitable_id]
  let event = EventCode::decode(event)
  match event {
    FutureRead | FutureWrite | StreamRead | StreamWrite => {
      let status = WaitableStatus::decode(code)
      match status {
        Completed(_) => waitable.run()
        Cancelled(_) | Dropped(_) => waitable.cancel()
        Blocking => return CallbackCode::Wait(waitable_id).encode()
      }
    }
    Subtask => {
      let status = SubtaskStatus::decode(code)
      match status {
        Starting(_) | Started(_) =>
          return CallbackCode::Wait(waitable_id).encode()
        Returned(_) => waitable.run()
        StartCancelled(_) | ReturnCancelled(_) => waitable.cancel()
      }
    }
    TaskCancel => waitable.cancel()
    EventNone => () // unreachable
  }
  @coroutine.rschedule()
  if waitable.is_done() {
    return CallbackCode::Exit.encode()
  }
  return CallbackCode::Wait(waitable_id).encode()
}

///|
pub fn WaitableTask::with_waitable_set(
  self : Self,
  f : async (Self) -> Unit raise,
  is_drop? : Bool = false,
) -> Unit noraise {
  let parent = @coroutine.spawn(fn() {
    defer (if self.tasks.is_empty() {
      task_map.remove(self.id)
      if is_drop {
        // runner will drop the waitable set
        // export async function needs to keep the waitable set
        self.drop()
      }
    })
    f(self)
  })
  parent.run()
  @coroutine.rschedule() // start the parent coroutine 
}

///|
pub fn current_waitable_set() -> WaitableTask? {
  let id = context_get()
  task_map.get(id)
}

///|
pub fn get_or_create_waitable_set() -> WaitableTask {
  guard current_waitable_set() is Some(ctx) else {
    let ctx = WaitableTask::new()
    task_map[ctx.id] = ctx
    return ctx
  }
  ctx
}

///|
pub fn set_active_task_context(ctx : Int) -> Unit {
  context_set(ctx)
}
