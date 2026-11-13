import cloud/connections/bsky
import cloud/connections/github
import cloud/connections/hacker_news
import cloud/connections/lobsters
import cloud/connections/rss
import cloud/data
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/string

fn field(value, name) {
  let assert v.Tagged(_, v.Record(fields)) = value
  let assert Ok(value) = dict.get(fields, name)
  value
}

fn tag(value) {
  let assert v.Tagged(tag, _) = value
  tag
}

const api_events =
  "[
  {\"id\": \"3\", \"type\": \"WatchEvent\", \"actor\": {\"login\": \"bob\"}, \"repo\": {\"name\": \"eyg/eyg\"}, \"payload\": {\"action\": \"started\"}},
  {\"id\": \"2\", \"type\": \"PushEvent\", \"actor\": {\"login\": \"alice\"}, \"repo\": {\"name\": \"eyg/eyg\"}, \"payload\": {\"ref\": \"refs/heads/main\", \"commits\": [{\"sha\": \"abc\", \"id\": \"abc\", \"message\": \"Fix parser\", \"author\": {\"name\": \"Alice\"}}]}},
  {\"id\": \"1\", \"type\": \"IssuesEvent\", \"actor\": {\"login\": \"carol\"}, \"repo\": {\"name\": \"eyg/eyg\"}, \"payload\": {\"action\": \"opened\", \"issue\": {\"number\": 7, \"title\": \"Crash\", \"body\": null, \"html_url\": \"https://github.com/eyg/eyg/issues/7\", \"labels\": [{\"name\": \"bug\"}]}}}
]"

pub fn github_api_events_test() {
  let assert Ok([star, push, issue]) = github.from_api("github", api_events)
  assert tag(star.value) == "GitHubStar"
  assert star.summary == "bob starred eyg/eyg"
  assert tag(push.value) == "GitHubPush"
  assert field(push.value, "branch") == data.string("main")
  let assert v.LinkedList([commit]) = field(push.value, "commits")
  let assert v.Record(commit) = commit
  assert dict.get(commit, "message") == Ok(data.string("Fix parser"))
  assert issue.id == "1"
  assert field(issue.value, "number") == data.int(7)
  assert field(issue.value, "body") == data.string("")
  assert field(issue.value, "labels") == data.strings(["bug"])
  assert field(issue.value, "actor") == data.string("carol")
}

const pull_request =
  "{
  \"action\": \"closed\",
  \"repository\": {\"full_name\": \"eyg/eyg\"},
  \"sender\": {\"login\": \"alice\"},
  \"pull_request\": {\"number\": 9, \"title\": \"Add triggers\", \"body\": \"\", \"merged\": true,
    \"html_url\": \"https://github.com/eyg/eyg/pull/9\", \"head\": {\"ref\": \"triggers\"}, \"base\": {\"ref\": \"main\"}}
}"

pub fn github_webhook_test() {
  let assert Ok(event) =
    github.from_webhook("github", "pull_request", "d1", pull_request)
  assert event.live
  assert event.id == "d1"
  assert tag(event.value) == "GitHubPullRequest"
  assert field(event.value, "merged") == data.bool(True)
  assert field(event.value, "base") == data.string("main")
  assert event.summary == "alice closed pull request #9"
}

pub fn github_signature_test() {
  let signature =
    "sha256="
    <> {
      crypto.hmac(<<"{}":utf8>>, crypto.Sha256, <<"s3cret":utf8>>)
      |> bit_array.base16_encode
      |> string.lowercase
    }
  assert github.verify("s3cret", "{}", signature)
  assert !github.verify("other", "{}", signature)
  assert !github.verify("s3cret", "{}", "")
}

const feed =
  "{\"feed\": [
  {\"post\": {\"uri\": \"at://did:plc:x/app.bsky.feed.post/3abc\", \"author\": {\"handle\": \"gleam.run\", \"displayName\": \"Gleam\"},
    \"record\": {\"text\": \"Gleam v2 is out\", \"createdAt\": \"2026-11-12T10:00:00Z\"}, \"likeCount\": 10, \"repostCount\": 2, \"replyCount\": 1}},
  {\"post\": {\"uri\": \"at://did:plc:y/app.bsky.feed.post/3def\", \"author\": {\"handle\": \"other.bsky.social\"}, \"record\": {\"text\": \"reposted\"}},
    \"reason\": {\"$type\": \"app.bsky.feed.defs#reasonRepost\"}}
]}"

pub fn bsky_feed_test() {
  let assert Ok([post]) = bsky.from_feed("bsky", "@gleam.run", feed)
  assert post.id == "at://did:plc:x/app.bsky.feed.post/3abc"
  assert tag(post.value) == "BskyPost"
  assert field(post.value, "url")
    == data.string("https://bsky.app/profile/gleam.run/post/3abc")
  assert field(post.value, "author") == data.string("Gleam")
  assert field(post.value, "likes") == data.int(10)
  assert field(post.value, "reply") == data.bool(False)
}

const rss_document =
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<rss version=\"2.0\"><channel><title>Blog</title>
<item><title>Second – post</title><link>https://example.com/2</link><guid>2</guid><description><![CDATA[<p>Hello</p>]]></description><pubDate>Thu, 12 Nov 2026 10:00:00 GMT</pubDate></item>
<item><title>First</title><link>https://example.com/1</link></item>
</channel></rss>"

const atom_document =
  "<feed xmlns=\"http://www.w3.org/2005/Atom\"><title>Atom</title>
<entry><id>tag:example.com,1</id><title>Entry</title><link href=\"https://example.com/e\"/><summary>Short</summary><updated>2026-11-12T10:00:00Z</updated></entry>
</feed>"

pub fn rss_test() {
  let assert Ok([second, first]) =
    rss.from_feed("feeds", "https://example.com/feed", rss_document)
  assert second.id == "2"
  assert field(second.value, "title") == data.string("Second – post")
  assert field(second.value, "summary") == data.string("<p>Hello</p>")
  assert field(second.value, "published")
    == data.string("Thu, 12 Nov 2026 10:00:00 GMT")
  // Items without a guid are identified by their link.
  assert first.id == "https://example.com/1"
}

pub fn atom_test() {
  let assert Ok([entry]) =
    rss.from_feed("feeds", "https://example.com/atom", atom_document)
  assert entry.id == "tag:example.com,1"
  assert field(entry.value, "link") == data.string("https://example.com/e")
  assert field(entry.value, "summary") == data.string("Short")
}

pub fn invalid_feed_test() {
  let assert Error(_) = rss.from_feed("feeds", "https://example.com", "<rss")
}

pub fn hacker_news_test() {
  let assert Ok(story) =
    hacker_news.from_item(
      "hn",
      "top",
      "{\"by\":\"dhouston\",\"descendants\":71,\"id\":8863,\"score\":104,\"title\":\"My YC app\",\"type\":\"story\"}",
    )
  assert story.id == "8863"
  // Stories without a url link to their comments.
  assert field(story.value, "url")
    == data.string("https://news.ycombinator.com/item?id=8863")
  assert field(story.value, "comments") == data.int(71)
}

pub fn lobsters_test() {
  let assert Ok([story]) =
    lobsters.from_page(
      "lobsters",
      "newest",
      "[{\"short_id\":\"ab12\",\"title\":\"Gleam\",\"url\":\"\",\"score\":3,\"comment_count\":1,\"submitter_user\":\"nemin\",\"tags\":[\"plt\"],\"comments_url\":\"https://lobste.rs/s/ab12/gleam\"}]",
    )
  assert story.id == "ab12"
  assert field(story.value, "url")
    == data.string("https://lobste.rs/s/ab12/gleam")
  assert field(story.value, "tags") == data.strings(["plt"])
}
