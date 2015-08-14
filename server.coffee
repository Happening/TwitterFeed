Db = require 'db'
Event = require 'event'
Http = require 'http'
OAuth = require 'oauth'
Photo = require 'photo'
Plugin = require 'plugin'
Subscription = require 'subscription'

exports.onInstall = (cfg) !->
	Db.backend.set "cfg", cfg if cfg?.twitterName
	fetch()

exports.clients_fetch = fetch = !->
	return unless twitterName = Db.backend.get("cfg","twitterName")
	Db.shared.set "lastFetch", 0|Plugin.time()
	request =
		url: "https://api.twitter.com/1.1/statuses/user_timeline.json/?screen_name=#{encodeURIComponent(twitterName)}&count=15&include_rts=false&contributor_details=false&exclude_replies=true&trim_user=true&since_id=#{encodeURIComponent(Db.shared.get("lastTweet")||0)}"
		name: "handleTweets"
	OAuth.sign request, ["jpbevbl1hxvd0yzXmJoHHkBJi","jA60cePhOeJUZ03I7wlaf0dptbgVIv0RxVBSREXkhfWTgyrGuh"]
	Http.get request

exports.handleTweets = (body) !->
	log 'body', body

	lastTweet = oldLastTweet = Db.backend.get("twitter","lastTweet") || 0
	Db.shared.set "lastReceive", 0|Plugin.time()

	body = JSON.parse body || []
	for tweet in body
		lastTweet = tweet.id if tweet.id > lastTweet
		post =
			time: 0 | ((new Date(tweet.created_at)).getTime()/1000)
			text: tweet.text
		if (photo = tweet.entities?.media?[0]) and photo.type=="photo"
			post.photo = photo.media_url_https

		maxId = Db.shared.incr('maxId')
		Db.shared.set(maxId, post)

	if lastTweet != oldLastTweet
		lastTweet = Db.backend.set "twitter","lastTweet", lastTweet

exports.getTitle = -> # we implemented our own title input
	if twitterName = Db.backend.get("cfg", "twitterName")
		return "Tweets @#{twitterName}"

exports.client_remove = (id) !->
	return if Plugin.userId() isnt Db.shared.get(id, 'by') and !Plugin.userIsAdmin()

	# remove any associated photos
	Photo.remove photo if photo = Db.shared.get(id, 'photo')

	Db.shared.remove(id)
