# bigorangeqwq/async-wasm(WIP)


Fork from `moonbitlang/async`, adapt to wasm async component model 


## Usage

```wit
interface i {
  str-argument-and-result: async func(x: string) -> string;
}

world test {
  export i;
}

world runner {
  import i;
}
```

```moonbit
///|
/// user implementation
pub async fn async_str_argument_and_result(x : String) -> String noraise {
  assert_eq(x, "hello") catch {
    _ => panic()
  }
  "world"
}

///|
/// generated
pub fn async_str_argument_and_result_callback(
  event_raw : Int,
  waitable : Int,
  code : Int,
) -> Int {
  @async.callback(event_raw, waitable, code)
}

///|
/// generated & export
pub fn wasmExportAsyncStrArgumentAndResult(p0 : Int, p1 : Int) -> Int {
  let result = @ffi.ptr2str(p0, p1)
  let task = @component.get_or_create_waitable_set()
  task.with_waitable_set(_ => {
    let result0 : String = async_str_argument_and_result(result)
    world_test_async_str_argument_and_result_task_return(result0)
  })
  return @ffi.CallbackCode::Wait(task.id).encode()
}

///|
/// generated & export
pub fn wasmExportworldTestAsyncAsyncStrArgumentAndResult(
  event_raw : Int,
  waitable : Int,
  code : Int,
) -> Int {
  async_str_argument_and_result_callback(event_raw, waitable, code)
}

///|
/// generated & import
fn wasmExportworldTestAsyncAsyncStrArgumentAndResultTaskReturn(p0: Int, p1: Int) = "[export]a:b/i" "[task-return][async]str-argument-and-result"

///|
/// generated
pub fn world_test_async_str_argument_and_result_task_return(result0: String) -> Unit {
      wasmExportworldTestAsyncAsyncStrArgumentAndResultTaskReturn(@ffi.str2ptr(result0), result0.length())
}
```