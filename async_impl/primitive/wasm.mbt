///|
pub(open) trait Waitable {
  update(Self, code~ : Int) -> Unit
  cancel(Self) -> Unit

  // try to drop waitable, if it is dropped, return true
  drop(Self) -> Bool
  done(Self) -> Bool
  handle(Self) -> Int
  ty(Self) -> WaitableType
}

///|
pub enum WaitableType {
  Future
  Stream
  Subtask
}

///|
pub(all) enum SubtaskStatus {
  Starting(Int)
  Started(Int)
  Returned(Int)
  StartCancelled(Int)
  ReturnCancelled(Int)
} derive(Eq, Show)

///|
pub fn SubtaskStatus::from(code : Int) -> SubtaskStatus {
  let handle = code >> 4
  match code & 0xf {
    0 => Starting(handle)
    1 => Started(handle)
    2 => Returned(handle)
    3 => StartCancelled(handle)
    4 => ReturnCancelled(handle)
    _ => panic()
  }
}

///|
pub fn SubtaskStatus::handle(self : Self) -> Int {
  match self {
    Starting(handle) => handle
    Started(handle) => handle
    Returned(handle) => handle
    StartCancelled(handle) => handle
    ReturnCancelled(handle) => handle
  }
}

///|
pub(all) enum Event {
  None
  Subtask
  StreamRead
  StreamWrite
  FutureRead
  FutureWrite
  TaskCancel
} derive(Eq, Show)

///|
pub fn Event::from(code : Int) -> Event {
  match code {
    0 => None
    1 => Subtask
    2 => StreamRead
    3 => StreamWrite
    4 => FutureRead
    5 => FutureWrite
    6 => TaskCancel
    _ => panic()
  }
}

///|
pub fn Event::code(self : Self) -> Int {
  match self {
    None => 0
    Subtask => 1
    StreamRead => 2
    StreamWrite => 3
    FutureRead => 4
    FutureWrite => 5
    TaskCancel => 6
  }
}

///|
pub(all) enum WaitableStatus {
  Completed(Int)
  Dropped(Int)
  Cancelled(Int)
  Blocking
  NotSure
} derive(Eq, Show)

///|
let waitable_status_block : Int = 0xffff_ffff

///|
pub fn WaitableStatus::from(code : Int) -> WaitableStatus {
  if code == waitable_status_block {
    return Blocking
  }
  let amt = code >> 4
  match code & 0xf {
    0 => Completed(amt)
    1 => Dropped(amt)
    2 => Cancelled(amt)
    _ => panic()
  }
}

///|
pub fn WaitableStatus::count(code : Int) -> Int {
  code >> 4
}

///|
pub(all) enum CallbackCode {
  Exit
  Yield
  Wait(Int)
  Cancel(Int)
} derive(Eq, Show)

///|
pub fn CallbackCode::code(self : Self) -> Int {
  match self {
    Exit => 0
    Yield => 1
    Wait(handle) => 2 | (handle << 4)
    Cancel(id) => 3 | (id << 4)
  }
}

///|
pub fn CallbackCode::from(code : Int) -> CallbackCode {
  let handle = code >> 4
  match code & 0xf {
    0 => Exit
    1 => Yield
    2 => Wait(handle)
    3 => Cancel(handle)
    _ => panic()
  }
}

///|
pub struct FutureVTable[T] {
  new : () -> UInt64
  read : (Int, Int) -> Int
  write : (Int, Int) -> Int
  cancel_read : (Int) -> Int
  cancel_write : (Int) -> Int
  drop_readable : (Int) -> Unit
  drop_writable : (Int) -> Unit
  malloc : (Int) -> Int
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
  malloc : (Int) -> Int,
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
pub fn[T] new_future(
  vtable : FutureVTable[T],
) -> (FutureReader[T], FutureWriter[T]) {
  let handle = (vtable.new)()
  let left_handle = handle.to_int()
  let right_handle = (handle >> 32).to_int()
  (
    FutureReader::new(left_handle, vtable),
    FutureWriter::new(right_handle, vtable),
  )
}

///|
pub struct FutureReader[T] {
  handle : Int
  vtable : FutureVTable[T]
  mut code : Int?
  mut dropped : Bool
  memory_refs : Array[Int]
}

///|
pub impl[T] Waitable for FutureReader[T] with update(self, code~ : Int) -> Unit {
  self.code = Some(code)
}

///|
pub impl[T] Waitable for FutureReader[T] with handle(self) -> Int {
  self.handle
}

///|
pub impl[T] Waitable for FutureReader[T] with cancel(self) -> Unit {
  if self.code is Some(code) && WaitableStatus::from(code) is Cancelled(_) {
    return
  }
  self.code = Some((self.vtable.cancel_read)(self.handle))
}

///|
pub impl[T] Waitable for FutureReader[T] with drop(self) -> Bool {
  _async_debug("stream-reader-drop(\{self.handle})")
  if self.dropped {
    return false
  }
  (self.vtable.drop_readable)(self.handle)
  self.dropped = true
  for ptr in self.memory_refs {
    (self.vtable.free)(ptr)
  }
  true
}

///|
pub impl[T] Waitable for FutureReader[T] with done(self) -> Bool {
  match self.code {
    Some(c) =>
      match WaitableStatus::from(c) {
        Completed(_) | Dropped(_) | Cancelled(_) => true
        Blocking | NotSure => false
        
      }
    None => false
  }
}

///|
pub impl[T] Waitable for FutureReader[T] with ty(self) -> WaitableType {
  ignore(self)
  WaitableType::Future
}

///|
pub fn[T] FutureReader::new(
  handle : Int,
  vtable : FutureVTable[T],
) -> FutureReader[T] {
  { handle, vtable, code: None, memory_refs: [], dropped: false }
}

///|
pub struct FutureWriter[T] {
  handle : Int
  vtable : FutureVTable[T]
  mut code : Int?
  mut dropped : Bool
  memory_refs : Array[Int]
}

///|
pub fn[T] FutureWriter::new(
  handle : Int,
  vtable : FutureVTable[T],
) -> FutureWriter[T] {
  { handle, vtable, code: None, memory_refs: [], dropped: false }
}

///|
pub impl[T] Waitable for FutureWriter[T] with update(self, code~ : Int) -> Unit {
  self.code = Some(code)
}

///|
pub impl[T] Waitable for FutureWriter[T] with handle(self) -> Int {
  self.handle
}

///|
pub impl[T] Waitable for FutureWriter[T] with cancel(self) -> Unit {
  if self.code is Some(code) && WaitableStatus::from(code) is Cancelled(_) {
    return
  }
  self.code = Some((self.vtable.cancel_write)(self.handle))
}

///|
pub impl[T] Waitable for FutureWriter[T] with drop(self) -> Bool {
  _async_debug("stream-writer-drop(\{self.handle})")
  if self.dropped {
    return false
  }
  (self.vtable.drop_writable)(self.handle)
  self.dropped = true
  for ptr in self.memory_refs {
    (self.vtable.free)(ptr)
  }
  true
}

///|
pub impl[T] Waitable for FutureWriter[T] with done(self) -> Bool {
  match self.code {
    Some(c) =>
      match WaitableStatus::from(c) {
        Completed(_) | Dropped(_) | Cancelled(_) => true
        Blocking | NotSure => false
      }
    None => false
  }
}

///|
pub impl[T] Waitable for FutureWriter[T] with ty(self) -> WaitableType {
  ignore(self)
  WaitableType::Future
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
  malloc : (Int) -> Int
  free : (Int) -> Unit
  lift : (Int, Int) -> FixedArray[T]
  lower : (FixedArray[T]) -> Int
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
  malloc : (Int) -> Int,
  free : (Int) -> Unit,
  lift : (Int, Int) -> FixedArray[T],
  lower : (FixedArray[T]) -> Int,
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
pub fn[T] new_stream(
  vtable : StreamVTable[T],
) -> (StreamReader[T], StreamWriter[T]) {
  let handle = (vtable.new)()
  let left_handle = handle.to_int()
  let right_handle = (handle >> 32).to_int()
  (
    StreamReader::new(left_handle, vtable),
    StreamWriter::new(right_handle, vtable),
  )
}

///|
pub struct StreamReader[T] {
  handle : Int
  vtable : StreamVTable[T]
  mut code : Int?
  mut dropped : Bool
  memory_refs : Array[Int]
}

///|
pub fn[T] StreamReader::new(
  handle : Int,
  vtable : StreamVTable[T],
) -> StreamReader[T] {
  { handle, vtable, code: None, memory_refs: [], dropped: false }
}

///|
pub impl[T] Waitable for StreamReader[T] with update(self, code~ : Int) -> Unit {
  self.code = Some(code)
}

///|
pub impl[T] Waitable for StreamReader[T] with handle(self) -> Int {
  self.handle
}

///|
pub impl[T] Waitable for StreamReader[T] with cancel(self) -> Unit {
  if self.code is Some(code) && WaitableStatus::from(code) is Cancelled(_) {
    return
  }
  self.code = Some((self.vtable.cancel_read)(self.handle))
}

///|
pub impl[T] Waitable for StreamReader[T] with drop(self) -> Bool {
  _async_debug("stream-reader-drop(\{self.handle})")
  if self.dropped {
    return false
  }
  (self.vtable.drop_readable)(self.handle)
  self.dropped = true
  for ptr in self.memory_refs {
    (self.vtable.free)(ptr)
  }
  true
}

///|
pub impl[T] Waitable for StreamReader[T] with done(self) -> Bool {
  match self.code {
    Some(c) =>
      match WaitableStatus::from(c) {
        Completed(_) | Dropped(_) | Cancelled(_) => true
        Blocking  | NotSure=> false
      }
    None => false
  }
}

///|
pub impl[T] Waitable for StreamReader[T] with ty(self) -> WaitableType {
  ignore(self)
  WaitableType::Stream
}

///|
pub struct StreamWriter[T] {
  handle : Int
  vtable : StreamVTable[T]
  mut code : Int?
  mut dropped : Bool
  memory_refs : Array[Int]
}

///|
pub impl[T] Waitable for StreamWriter[T] with update(self, code~ : Int) -> Unit {
  self.code = Some(code)
}

///|
pub impl[T] Waitable for StreamWriter[T] with handle(self) -> Int {
  self.handle
}

///|
pub impl[T] Waitable for StreamWriter[T] with cancel(self) -> Unit {
  if self.code is Some(code) && WaitableStatus::from(code) is Cancelled(_) {
    return
  }
  self.code = Some((self.vtable.cancel_write)(self.handle))
}

///|
pub impl[T] Waitable for StreamWriter[T] with drop(self) -> Bool {
  _async_debug("stream-writer-drop(\{self.handle})")
  if self.dropped {
    return false
  }
  (self.vtable.drop_writable)(self.handle)
  self.dropped = true
  for ptr in self.memory_refs {
    (self.vtable.free)(ptr)
  }
  true
}

///|
pub impl[T] Waitable for StreamWriter[T] with done(self) -> Bool {
  match self.code {
    Some(c) =>
      match WaitableStatus::from(c) {
        Completed(_) | Dropped(_) | Cancelled(_) => true
        Blocking | NotSure => false
      }
    None => false
  }
}

///|
pub impl[T] Waitable for StreamWriter[T] with ty(self) -> WaitableType {
  ignore(self)
  WaitableType::Stream
}

///|
pub fn[T] StreamWriter::new(
  handle : Int,
  vtable : StreamVTable[T],
) -> StreamWriter[T] {
  { handle, vtable, code: None, memory_refs: [], dropped: false }
}


struct Subtask {
  handle: Int
  mut dropped: Bool
  mut code : Int?
}

///|
pub impl Waitable for Subtask with handle(self) -> Int {
  self.handle
}

pub impl Waitable for Subtask with update(self, code~ : Int) -> Unit {
  self.code = Some(code)
}

pub impl Waitable for Subtask with drop(self) -> Bool   {
  if not(self.dropped) {
    self.dropped = true
    _async_debug("drop-subtask(\{self.handle})")
    subtask_drop(self.handle)
    return true 
  }
  false
}

pub impl Waitable for Subtask with cancel(self) -> Unit {
  if self.code is Some(code) && WaitableStatus::from(code) is Cancelled(_) {
    return
  }
  self.code = Some(subtask_cancel(self.handle))
}

pub impl Waitable for Subtask with done(self) -> Bool {
  match self.code {
    Some(c) =>
      match SubtaskStatus::from(c) {
        Returned(_) | ReturnCancelled(_) => true
        Starting(_) | Started(_) | StartCancelled(_) => false
      }
    None => false
  }
}

pub impl Waitable for Subtask with ty(self) -> WaitableType {
  ignore(self)
  WaitableType::Subtask
}




///|
pub struct WaitableSet(Int)

///|
pub fn WaitableSet::new() -> WaitableSet {
  WaitableSet(waitable_set_new())
}

///|
pub fn WaitableSet::from_handle(handle : Int) -> WaitableSet {
  guard handle != 0
  WaitableSet(handle)
}

///|
pub fn WaitableSet::drop(self : WaitableSet) -> Unit {
  waitable_set_drop(self.0)
}

///|
pub fn WaitableSet::join(self : WaitableSet, waitable : Int) -> Unit {
  waitable_join(waitable, self.0)
}

///|
pub fn WaitableSet::remove_waitable(
  _self : WaitableSet,
  waitable : Int,
) -> Unit {
  waitable_join(waitable, 0)
}

///|
pub fn WaitableSet::poll(self : WaitableSet) -> (Int, Int, Int) {
  let result : FixedArray[Int] = FixedArray::make(2, 0)
  let result_ptr = int_array2ptr(result)
  let event0 = waitable_set_poll(self.0, result_ptr)
  (event0, result[0], result[1])
}

///|
pub fn WaitableSet::wait(self : WaitableSet) -> (Int, Int, Int) {
  let result : FixedArray[Int] = FixedArray::make(2, 0)
  let result_ptr = int_array2ptr(result)
  let event0 = waitable_set_wait(self.0, result_ptr)
  (event0, result[0], result[1])
}

///|
pub extern "wasm" fn int_array2ptr(array : FixedArray[Int]) -> Int =
  #|(func (param i32) (result i32) local.get 0 i32.const 8 i32.add)

///|
/// This function is empty, If you want to print debug info, you can hook it in your environment.
pub fn _async_debug(_msg : String) -> Unit {
  ()
}

// Component async primitives

///|
pub fn yield_blocking() -> Bool = "$root" "[yield]"

///|
pub fn backpressure_set() -> Int = "$root" "[backpressure-set]"

///|
pub fn subtask_cancel(task : Int) -> Int = "$root" "[subtask-cancel]"

///|
pub fn subtask_drop(task : Int) = "$root" "[subtask-drop]"

///|
pub fn context_set(task : Int) = "$root" "[context-set-0]"

///|
pub fn context_get() -> Int = "$root" "[context-get-0]"

///|
pub fn task_cancel() = "[export]$root" "[task-cancel]"

///|
pub fn waitable_set_new() -> Int = "$root" "[waitable-set-new]"

///|
pub fn waitable_set_drop(set : Int) = "$root" "[waitable-set-drop]"

///|
pub fn waitable_join(waitable : Int, set : Int) = "$root" "[waitable-join]"

///|
pub fn waitable_set_wait(set : Int, ptr : Int) -> Int = "$root" "[waitable-set-wait]"

///|
pub fn waitable_set_poll(set : Int, ptr : Int) -> Int = "$root" "[waitable-set-poll]"
