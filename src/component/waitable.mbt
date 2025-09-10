// 基底为 coroutine，其中字段为 code: Int，管理 Future/Stream 等状态

pub(open) trait Waitable {
  // run with code
  update(Self, code~: Int) -> Unit

  // receive cancel signal do something
  cancel(Self) -> Int

  // drop the waitable resource
  drop(Self) -> Unit

  // check if the waitable is done
  is_done(Self) -> Bool

  // get the waitable handle
  handle(Self) -> Int
}
