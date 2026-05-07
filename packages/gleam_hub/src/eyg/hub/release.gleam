import multiformats/cid/v1

pub type Release {
  Release(package: String, version: Int, module: v1.Cid)
}
