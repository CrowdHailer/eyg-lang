import bucket
import bucket/get_object
import bucket/list_objects
import bucket/put_object
import cloud/config
import gleam/httpc
import gleam/string
import multiformats/cid/v1

pub type Error {
  HttpError(httpc.HttpError)
  BucketError(bucket.BucketError)
}

pub fn list(config: config.S3Bucket) {
  let request =
    list_objects.request(config.bucket)
    |> list_objects.build(config.credentials)
  sent(request, list_objects.response)
}

pub fn get(config: config.S3Bucket, key: v1.Cid) {
  let request =
    get_object.request(config.bucket, v1.to_string(key))
    |> get_object.build(config.credentials)
  sent(request, get_object.response)
}

pub fn put(config: config.S3Bucket, key: v1.Cid, bytes: BitArray) {
  let request =
    put_object.request(config.bucket, v1.to_string(key), bytes)
    |> put_object.build(config.credentials)
  sent(request, put_object.response)
}

fn sent(request, decode_response) {
  case httpc.send_bits(request) {
    Ok(response) ->
      case decode_response(response) {
        Ok(response) -> Ok(response)
        Error(reason) -> Error(BucketError(reason))
      }
    Error(reason) -> Error(HttpError(reason))
  }
}

pub fn describe_reason(reason) {
  string.inspect(reason)
}
