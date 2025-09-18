
```moonbit
async fn future_read() -> String {
      // primitive async read
      // block_state
      // suspend
      // wait for callback
      // read from memory
      // return
      ...
}

// 低层的 import 
// pub async importAsyncFunc() -> Int {
//       @coro.spawn(async_func()) // 应该交给coro的一个全局变量去处理
//       return Int // 然后成为甩手掌柜，不管它是否是 第一次 Exit， 都 Await，直到下次 callback 再 Exit
// }


/// auto callback func
/// pub async callback_omg(event_raw: Int, waitable: Int, code: Int) -> Int {
/// 
/// }

// 这个函数应该是callback的相关函数
// 把原语 async 组合成普通的 @coro.spawn(async_func)) 形式，再alias future.async_read
// 应该长这样，spawn 签名就是 spawn(() -> Unit) -> ....
// @coro.spawn(fn() { async_omg_return(async_omg(xxxxx)) })
// 理论上函数里面每有一个 async 函数，都应该有一个 callback 的状态与之对应，并且在callback的时候suspend回来继续运行
pub fn async_omg(x: @ffi.Future[String]) -> ResultType {


      let result = x.async_read() //等待它       
      // 函数内每有一个 async 函数，都应该有一个 callback 的 state 
      // @coro.spawn(async_func2())
      // 等待下次 suspend 到此

      
      return result
}

// 对于 runner 来说， block-on 主要是通过 wait 和 poll 循环获取 waitable set 的结果
// 直到有可以运行的就返回
// 标注 inline 的意味着为生成

/// runner

pub fn inline_async_sasync(id : @ffi.Stream[UInt]) -> UserInfo {

      let result_ptr = @ffi.malloc(24);
      // You must manually check and handle subtask_status to ensure the async task returns correctly.
      let subtask_status = @ffi.SubtaskStatus::decode(wasmImportAsyncSasync(id.0, result_ptr))
      match subtask_status {
            Returned => ()
            _ => @coroutine.suspend()
      } 
      let result = @ffi.ptr2str(@ffi.load32((result_ptr) + 4), @ffi.load32((result_ptr) + 8))
      let result0 = @ffi.ptr2str(@ffi.load32((result_ptr) + 12), @ffi.load32((result_ptr) + 16))
      UserInfo::{id : (@ffi.load32((result_ptr) + 0)).reinterpret_as_uint(), name : result, email : result0, age : (@ffi.load8_u((result_ptr) + 20)).to_byte(), is_active : (@ffi.load8_u((result_ptr) + 21) != 0)}
}

pub fn main() {
      @async.async_event_loop(task: WaitableTask) {
            let result = task.wait(inline_async_sasync())
            ...
            // defer will drop task
      }
}


/// test

pub fn inline_async_omg_callback(event_raw: Int, waitable: Int, code: Int) -> Int {
      @ffi.callback(event_raw, waitable, code)
}

pub fn async_omg() -> UserInfo {
      ...
}

pub fn inline_async_async_omg() -> Int {
      @async.with_waitable_set(fn(task) {
            task.spawn(() => world_test_async_omg_task_return(async_omg()))
      })
      return @ffi.CallbackCode::Wait(task.id)
}
```


```
      let subtask_status = @ffi.SubtaskStatus::decode(wasmImportAsyncOmg3((id).reinterpret_as_int(), result_ptr))

      task.await(async fn() {
            let handle_id = subtask_status.handle()
            // init subtask
            while status {
                  suspend() ...
                  done() ...
            }
      })
```

