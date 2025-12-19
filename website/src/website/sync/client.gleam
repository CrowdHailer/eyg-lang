import website/sync/cache

// initialize and start pull
pub type Client {
  Client(cache: cache.Cache)
}

pub type Message {
  ReleasesFetched
  FragmentFetched
}

pub fn init(origin) -> #(Client, _) {
  todo
}

pub fn update(client, message) -> #(Client, _) {
  todo
}

pub fn lustre_run(task, m) {
  todo
}
