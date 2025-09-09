// 基底为 coroutine，其中字段为 code: Int，管理 Future/Stream 等状态

pub(open) trait WaitableTrait {
  // run with code
  update(Self, code~: Int) -> Unit
  // subtask/future/stream can cancel itself
  cancel(Self) -> Int

  drop(Self) -> Unit

  is_done(Self) -> Bool
  
  defer_task(Self) -> Unit raise

  handle(Self) -> Int
}
