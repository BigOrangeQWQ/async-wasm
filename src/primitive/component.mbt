///|
pub(all) enum SubtaskStatus {
  Starting = 0
  Started = 1
  Returned = 2
  StartCancelled = 3
  ReturnCancelled = 4
}

///|
pub fn SubtaskStatus::decode(int : Int) -> SubtaskStatus {
  match int & 0xf {
    0 => Starting
    1 => Started
    2 => Returned
    3 => StartCancelled
    4 => ReturnCancelled
    _ => panic()
  }
}

///|
pub fn SubtaskStatus::encode(self : Self) -> Int {
  match self {
    Starting => 0
    Started => 1
    Returned => 2
    StartCancelled => 3
    ReturnCancelled => 4
  }
}

///|
pub(all) enum EventCode {
  EventNone = 0
  Subtask = 1
  StreamRead = 2
  StreamWrite = 3
  FutureRead = 4
  FutureWrite = 5
  Cancel = 6
}

///|
pub fn EventCode::decode(int : Int) -> EventCode {
  match int {
    0 => EventNone
    1 => Subtask
    2 => StreamRead
    3 => StreamWrite
    4 => FutureRead
    5 => FutureWrite
    6 => Cancel
    _ => panic()
  }
}

///|
pub fn EventCode::encode(self : Self) -> Int {
  match self {
    EventNone => 0
    Subtask => 1
    StreamRead => 2
    StreamWrite => 3
    FutureRead => 4
    FutureWrite => 5
    Cancel => 6
  }
}

///|
pub(all) enum WaitableStatus {
  Completed(Int)
  Dropped(Int)
  Cancelled(Int)
  Block
}

///|
let waitable_status_block : Int = 0xffff_ffff

///|
pub fn WaitableStatus::decode(int : Int) -> WaitableStatus {
  if int == waitable_status_block {
    return Block
  }
  let amt = int >> 4
  match int & 0xf {
    0 => Completed(amt)
    1 => Dropped(amt)
    2 => Cancelled(amt)
    _ => panic()
  }
}

///|
pub fn WaitableStatus::count(int : Int) -> Int {
  int >> 4
}

///|
pub enum CallbackCode {
  Exit
  Yield
  Wait(Int)
  Cancel(Int)
}

///|
pub fn CallbackCode::encode(self : Self) -> Int {
  match self {
    Exit => 0
    Yield => 1
    Wait(id) => 2 | (id << 4)
    Cancel(id) => 3 | (id << 4)
  }
}

///|
pub fn CallbackCode::decode(int : Int) -> CallbackCode {
  let id = int >> 4
  match int & 0xf {
    0 => Exit
    1 => Yield
    2 => Wait(id)
    3 => Cancel(id)
    _ => panic()
  }
}

// Component async primitives

///|
#cfg(target="wasm")
pub fn yield_blocking() -> Bool = "$root" "[yield]"

///|
#cfg(target="wasm")
pub fn backpressure_set() -> Int = "$root" "[backpressure_set]"

///|
#cfg(target="wasm")
pub fn subtask_cancel(id : Int) -> Int = "$root" "[subtask_cancel]"

///|
#cfg(target="wasm")
pub fn subtask_drop(id : Int) = "$root" "[subtask_drop]"

///|
#cfg(target="wasm")
pub fn waitable_set_new() -> Int = "$root" "[waitable-set-new]"

///|
#cfg(target="wasm")
pub fn waitable_set_drop(set : Int) = "$root" "[waitable-set-drop]"

///|
#cfg(target="wasm")
pub fn waitable_join(waitable : Int, set : Int) = "$root" "[waitable-join]"

///|
#cfg(target="wasm")
pub fn waitable_set_wait(set : Int, result_ptr : Int) -> Int = "$root" "[waitable-set-wait]"

///|
#cfg(target="wasm")
pub fn waitable_set_poll(set : Int, result_ptr : Int) -> Int = "$root" "[waitable-set-poll]"
