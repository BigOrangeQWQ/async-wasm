///|
pub struct WaitableSet(Int)

///|
pub fn WaitableSet::new() -> WaitableSet {
  waitable_set_new()
}

///|
pub fn WaitableSet::from_raw(raw : Int) -> WaitableSet {
  guard raw != 0 else { panic() }
  WaitableSet(raw)
}

///|
pub fn WaitableSet::join(self : WaitableSet, waitable : Int) -> Unit {
  waitable_join(waitable, self.as_raw())
}

///|
pub fn WaitableSet::remove_waitable_from_all_sets(waitable : Int) -> Unit {
  waitable_join(0, waitable)
}

///|
pub fn WaitableSet::wait(self : Self) -> (Int, Int, Int) {
  let result : FixedArray[Int] = FixedArray::make(2, 0)
  let result_ptr = int_array2ptr(result)
  let event0 = waitable_set_wait(self.as_raw(), result_ptr)
  (event0, result[0], result[1])
}

///|
pub fn WaitableSet::poll(self : Self) -> (Int, Int, Int) {
  let result : FixedArray[Int] = FixedArray::make(2, 0)
  let result_ptr = int_array2ptr(result)
  let event0 = waitable_set_poll(self.as_raw(), result_ptr)
  (event0, result[0], result[1])
}

///|
pub fn WaitableSet::drop(self : Self) -> Unit {
  waitable_set_drop(self.as_raw())
}

///|
pub fn WaitableSet::as_raw(self : Self) -> Int {
  self.0
}
