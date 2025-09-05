///|
pub enum TaskStatus {
  Fail(Error)
  Running
  Done
}

///|
pub struct WaitableTask {
  id : Int
  tasks : Map[Int, @coroutine.Coroutine]
  task_defer : Array[() -> Unit raise]
  mut status : TaskStatus
} // TaskGroup

///|
pub let task_map : Map[Int, WaitableTask] = {}

///|
/// this avoids multiple lookups of current waitable task context
let curr_task : Ref[WaitableTask?] = Ref::new(None)

///|
pub fn WaitableTask::new() -> WaitableTask {
  let waitable_set = waitable_set_new()
  activate_waitable_task_context(waitable_set)
  { id: waitable_set, tasks: {}, task_defer: [], status: Running }
}

///|
pub fn WaitableTask::from_raw(raw : Int) -> WaitableTask {
  guard raw != 0
  activate_waitable_task_context(raw)
  { id: raw, tasks: {}, task_defer: [], status: Running }
}

///|
pub fn WaitableTask::add_waitable(self : Self, waitable : Int) -> Unit {
  waitable_join(waitable, self.id)
}

///|
pub fn WaitableTask::wait(self : Self) -> (Int, Int, Int) {
  let result : FixedArray[Int] = FixedArray::make(2, 0)
  let result_ptr = int_array2ptr(result)
  let event0 = waitable_set_wait(self.id, result_ptr)
  (event0, result[0], result[1])
}

///|
pub fn WaitableTask::poll(self : Self) -> (Int, Int, Int) {
  let result : FixedArray[Int] = FixedArray::make(2, 0)
  let result_ptr = int_array2ptr(result)
  let event0 = waitable_set_poll(self.id, result_ptr)
  (event0, result[0], result[1])
}

///|
pub fn WaitableTask::remove_waitable(self : Self, waitable : Int) -> Unit {
  waitable_join(waitable, self.id)
  self.tasks.remove(waitable)
}

///|
pub fn WaitableTask::drop(self : Self) -> Unit {
  activate_waitable_task_context(0) // clear current context
  waitable_set_drop(self.id) // runner will drop the waitable set
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
pub fn WaitableTask::add_defer(self : Self, f : () -> Unit raise) -> Unit {
  self.task_defer.push(f)
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
) -> @coroutine.Coroutine noraise {
  let parent = @coroutine.spawn(async fn() -> Unit raise {
    defer (if self.tasks.is_empty() {
      self.status = Done
      task_map.remove(self.id)
      // runner will drop the waitable set
      // export async function needs to keep the waitable set
      if is_drop {
        self.drop()
      }

      // this defer block recycles waitable task resources
      while self.task_defer.pop() is Some(defer_block) {
        defer_block() catch {
          err => if self.status is Done { self.status = Fail(err) }
        }
      }
    })
    f(self)
  })
  parent.run()
  @coroutine.rschedule() // start the parent coroutine 
  parent
}

///|
pub fn current_waitable_set() -> WaitableTask? {
  return curr_task.val
}

///|
pub fn get_or_create_waitable_set() -> WaitableTask {
  let ctx = match current_waitable_set() {
    Some(ctx) => ctx
    None => {
      let ctx = WaitableTask::new()
      task_map[ctx.id] = ctx
      ctx
    }
  }
  curr_task.val = Some(ctx)
  ctx
}

///|
fn activate_waitable_task_context(ctx : Int) -> Unit {
  context_set(ctx)
}
