///|
pub fn with_event_loop(f : async (TaskGroup[Unit]) -> Unit raise) -> Unit raise {
  @event_loop.with_event_loop(() => with_task_group(f))
}

///|
pub fnalias @coroutine.pause

///|
pub fnalias @coroutine.protect_from_cancel

///|
pub fnalias @component.with_waitable_set
