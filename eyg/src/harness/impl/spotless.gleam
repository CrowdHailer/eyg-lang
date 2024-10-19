import harness/impl/spotless/dnsimple
import harness/impl/spotless/dnsimple/list_domains as dnsimple_list_domains
import harness/impl/spotless/gmail/list_messages as gmail_list_messages
import harness/impl/spotless/gmail/send as gmail_send
import harness/impl/spotless/google
import harness/impl/spotless/google_calendar/list_events as gcal_list_events
import harness/impl/spotless/netlify
import harness/impl/spotless/netlify/deploy_site as netlify_deploy_site
import harness/impl/spotless/netlify/list_sites as netlify_list_sites
import harness/impl/spotless/twitter
import harness/impl/spotless/twitter/tweet
import harness/impl/spotless/vimeo
import harness/impl/spotless/vimeo/my_videos as vimeo_my_videos

pub fn effects() {
  [
    #(
      dnsimple_list_domains.l,
      #(
        dnsimple_list_domains.lift(),
        dnsimple_list_domains.reply(),
        dnsimple_list_domains.blocking(dnsimple.local, _),
      ),
    ),
    #(google.l, #(google.lift, google.reply, google.blocking(google.local, _))),
    #(
      gmail_send.l,
      #(gmail_send.lift(), gmail_send.reply(), gmail_send.blocking(
        google.local,
        _,
      )),
    ),
    #(
      gcal_list_events.l,
      #(
        gcal_list_events.lift(),
        gcal_list_events.reply(),
        gcal_list_events.blocking(google.local, _),
      ),
    ),
    #(
      gmail_list_messages.l,
      #(
        gmail_list_messages.lift(),
        gmail_list_messages.reply(),
        gmail_list_messages.blocking(google.local, _),
      ),
    ),
    #(
      netlify.l,
      #(netlify.lift, netlify.reply, netlify.blocking(netlify.local, _)),
    ),
    #(
      vimeo_my_videos.l,
      #(vimeo_my_videos.lift, vimeo_my_videos.reply(), vimeo_my_videos.blocking(
        vimeo.local,
        _,
      )),
    ),
    #(
      netlify_list_sites.l,
      #(
        netlify_list_sites.lift,
        netlify_list_sites.reply(),
        netlify_list_sites.blocking(netlify.local, _),
      ),
    ),
    #(
      netlify_deploy_site.l,
      #(
        netlify_deploy_site.lift(),
        netlify_deploy_site.reply(),
        netlify_deploy_site.blocking(netlify.local, _),
      ),
    ),
    #(
      tweet.l,
      #(tweet.lift(), tweet.reply(), tweet.blocking(
        twitter.client_id,
        twitter.redirect_uri,
        _,
      )),
    ),
  ]
}
