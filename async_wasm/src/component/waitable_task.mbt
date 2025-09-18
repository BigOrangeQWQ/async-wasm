///|
enum TaskStatus {
  Fail(Error)
  Running
  Done
}

///|
pub struct Task {
  id : Int
  tasks : Map[Int, (&Waitable, @coroutine.Coroutine)]
  task_defer : Array[() -> Unit raise]
  mut status : TaskStatus
} // TaskGroup

///|
pub let task_map : Map[Int, Task] = {}

///|
pub fn Task::new() -> Task {
  let waitable_set = waitable_set_new()
  context_set(waitable_set)
  { id: waitable_set, tasks: {}, task_defer: [], status: Running }
}

///|
pub fn Task::from_raw(raw : Int) -> Task {
  guard raw != 0
  context_set(raw)
  { id: raw, tasks: {}, task_defer: [], status: Running }
}

///|
pub fn Task::is_done(self : Self) -> Bool {
  match self.status {
    Running => false
    Done | Fail(_) => true
  }
}

///|
pub fn Task::is_fail(self : Self) -> Error? {
  match self.status {
    Fail(err) => Some(err)
    _ => None
  }
}

///|
pub fn Task::blocking_wait(self : Self) -> (Int, Int, Int) {
  let result : FixedArray[Int] = FixedArray::make(2, 0)
  let result_ptr = int_array2ptr(result)
  let event0 = waitable_set_wait(self.id, result_ptr)
  (event0, result[0], result[1])
}

///|
pub fn Task::poll(self : Self) -> (Int, Int, Int) {
  let result : FixedArray[Int] = FixedArray::make(2, 0)
  let result_ptr = int_array2ptr(result)
  let event0 = waitable_set_poll(self.id, result_ptr)
  (event0, result[0], result[1])
}

///|
fn[T : Waitable] Task::add_waitable(self : Self, waitable : T) -> Unit {
  waitable_join(waitable.handle(), self.id)
}

///|
/// When a waitable is done will be removed from the waitable set
/// then waitable will be dropped
fn[T : Waitable] Task::remove_waitable(self : Self, waitable : T) -> Unit {
  waitable_join(waitable.handle(), self.id)
  let waitable = self.tasks.get(waitable.handle())
  guard waitable is Some((waitable, _)) else { return }
  waitable.drop()
  self.tasks.remove(waitable.handle())
}

///|
/// Drop the waitable set and all waitables in it
pub fn Task::drop(self : Self) -> Unit {
  // clear current task context
  context_set(0)
  // runner will drop the waitable set
  defer waitable_set_drop(self.id)
  // remove all waitables and drop them
  for task in self.tasks.values() {
    task.0.drop()
  }
  self.tasks.clear()
}

pub fn Task::cancel(self : Self) -> Unit {
  task_cancel()
  // remove all waitables and drop them
  for task in self.tasks.values() {
    task.0.drop()
  }
  self.tasks.clear() 
}

///|
pub fn Task::spawn(
  task : Self,
  f : async () -> Unit raise,
  state : &Waitable,
) -> Unit {
  let coro = @coroutine.spawn(fn() {
    task.add_waitable(state)
    defer task.remove_waitable(state)
    f()
  })
  task.tasks[state.handle()] = (state, coro)
}

///|
/// This function spawns a coroutine to run the async function and waits for its completion
pub async fn Task::wait(
  task : Self,
  f : async () -> Unit raise,
  state : &Waitable,
) -> Unit raise {
  let coro = @coroutine.spawn(fn() {
    task.add_waitable(state)
    defer task.remove_waitable(state)
    f()
  })
  task.tasks[state.handle()] = (state, coro)
  @coroutine.Coroutine::wait(coro)
}

///|
pub fn Task::add_defer(self : Self, f : () -> Unit raise) -> Unit {
  self.task_defer.push(f)
}

///|
/// This function is core of the wasm async runtime
/// It is called by the host when an event happens
pub fn callback(event : Int, waitable_id : Int, code : Int) -> Int {
  let event = Event::decode(event)
  // Handle the event for the current waitable task  
  match event {
    FutureRead | FutureWrite | StreamRead | StreamWrite | Subtask => {
      guard current_waitable_set() is Some(task)
      let (waitable, coro) = task.tasks[waitable_id]
      waitable.update(code~)
      coro.run()
      // schedule next coroutine
      @coroutine.rschedule()
      if waitable.is_done() {
        return CallbackCode::Exit.encode()
      }
      return CallbackCode::Wait(waitable_id).encode()
    }
    TaskCancel => {
      guard current_waitable_set() is Some(task)
      task.tasks
      .values()
      .each(task => {
        let _ = task.0.drop()
      })
      @coroutine.rschedule()
      return CallbackCode::Exit.encode()
    }
    None => {
      @coroutine.rschedule()
      return CallbackCode::Exit.encode()
    }
  }
}

///|
pub fn Task::with_waitable_set(
  self : Self,
  f : async (Self) -> Unit raise,
  is_drop? : Bool = false,
) -> Unit noraise {
  let mut is_drop = is_drop
  let parent = @coroutine.spawn(async fn() -> Unit {
    self.status = Running
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
    f(self) catch {
      err =>
        if self.status is Running {
          self.status = Fail(err)
          is_drop = true
        }
    }
  })
  parent.run()
  @coroutine.rschedule() // start the parent coroutine 
}

///|
pub fn current_waitable_set() -> Task? {
  let ctx = context_get()
  if ctx == 0 {
    None
  } else {
    match task_map.get(ctx) {
      Some(task) => Some(task)
      None => {
        let ctx = Task::from_raw(ctx)
        task_map[ctx.id] = ctx
        Some(ctx)
      }
    }
  }
}

///|
pub fn get_or_create_waitable_set() -> Task {
  let ctx = context_get()
  if ctx == 0 {
    let ctx = Task::new()
    task_map[ctx.id] = ctx
    ctx
  } else {
    match task_map.get(ctx) {
      Some(task) => task
      None => {
        let ctx = Task::from_raw(ctx)
        task_map[ctx.id] = ctx
        ctx
      }
    }

  }
}

///|
pub fn create_waitable_set() -> Task {
  guard current_waitable_set() is None
  Task::new()
}
