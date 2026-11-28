import bucket
import envoy
import gleam/option.{None}
import gleam/result.{try}
import ogre/origin

pub type Config {
  Config(secret_key_base: String, bucket: S3Bucket, postgres: Postgres)
}

pub type Postgres {
  Postgres(host: String, password: String)
}

pub type S3Bucket {
  S3Bucket(credentials: bucket.Credentials, bucket: String)
}

pub fn bucket() -> Result(S3Bucket, Nil) {
  use s3_endpoint <- try(envoy.get("S3_ENDPOINT"))
  use region <- try(envoy.get("S3_REGION"))
  use bucket <- try(envoy.get("S3_BUCKET"))
  use access_key_id <- try(envoy.get("S3_ACCESS_KEY_ID"))
  use secret_access_key <- try(envoy.get("S3_SECRET_ACCESS_KEY"))
  use origin.Origin(scheme:, host:, port:) <- try(origin.from_string_strict(
    s3_endpoint,
  ))
  let credentials =
    bucket.Credentials(
      scheme:,
      port:,
      host:,
      region:,
      access_key_id:,
      secret_access_key:,
      session_token: None,
    )
  S3Bucket(credentials:, bucket:)
  |> Ok
}

pub fn from_env() {
  use secret_key_base <- try(envoy.get("SECRET_KEY_BASE"))
  use bucket <- try(bucket())
  use postgres_host <- try(envoy.get("POSTGRES_HOST"))
  use postgres_password <- try(envoy.get("POSTGRES_PASSWORD"))
  let postgres = Postgres(host: postgres_host, password: postgres_password)
  Ok(Config(secret_key_base:, bucket:, postgres:))
}
