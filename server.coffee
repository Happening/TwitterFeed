Db = require 'db'
Event = require 'event'
Http = require 'http'
Timer = require 'timer'
OAuth = require 'oauth'
Photo = require 'photo'
App = require 'app'
Subscription = require 'subscription'

pollTime = 60
subscribeTime = 7200

pushSecret = 'bdgxfs$WCEF'

exports.onInstall = (cfg) !->
	if account = cfg?.account
		if account[0]=='@'
			account = account.substr 1
		cfg.account = account.toLowerCase()
		Db.shared.set "cfg", cfg
		subscribe()
		App.setTitle "@#{account} tweets"

exports.onUpgrade = !->
	account = Db.shared.get 'cfg', 'account'
	if account
		st = Db.shared.get 'status'
		newId = st.id
		while Db.shared.get(newId+1)
			newId++
		if st.id < newId
			log 'writing new max id', newId
			Db.shared.set 'status', 'id', newId

		orSt = Db.origin.get 'cache', account, 'status'
		if !orSt.id or newId > orSt.id
			log 'writing new origin max id', newId
			Db.origin.set 'cache', account, 'status', 'id', newId
		if !orSt.tweet or st.tweet > orSt.tweet
			log 'writing new origin tweet', st.tweet
			Db.origin.set 'cache', account, 'status', 'tweet', st.tweet


exports.client_subscribe = subscribe = !->

	return unless account = Db.shared.get("cfg","account")

	time = 0|App.time()
	Db.shared.set "subscribed", time

	Db.origin.set "cache", account, "subs", App.groupCode(), time

	if cacheStatus = Db.origin.get("cache", account, "status")
		# tweet: newest tweet id
		# fetch: last fetch time
		# id: max item id
		
		# copy any tweets we may have missed (because we were unsubscribed for some time, or because push didn't work)
		maxId = Db.shared.get("status", "id") || 0
		while ++maxId <= cacheStatus.id
			Db.shared.set maxId, Db.origin.get("cache", account, maxId)
		Db.shared.set "status", cacheStatus

		return if cacheStatus.fetch > App.time()-pollTime*2 # recent enough

	# The last fetch is at least 120s ago, which means there's probably no master. Let's become one!
	fetch account, cacheStatus?.tweet

fetch = (account, lastTweet) !->
	log 'fetch '+lastTweet
	Db.origin.set "cache", account, "status", "fetch", (0|App.time())
	request =
		url: "https://api.twitter.com/1.1/statuses/user_timeline.json?screen_name=#{encodeURIComponent(account)}&count=15&include_rts=true&contributor_details=false&exclude_replies=true&trim_user=true" + (if lastTweet then "&since_id=#{encodeURIComponent lastTweet}" else "")
		name: "handleTweets"
		args: [account]
	log request.url
	OAuth.sign request, ["jpbevbl1hxvd0yzXmJoHHkBJi","jA60cePhOeJUZ03I7wlaf0dptbgVIv0RxVBSREXkhfWTgyrGuh"]
	Http.get request

exports.poll = poll = (account) !->
	log 'poll'
	cacheStatus = Db.origin.get "cache", account, "status"
	if cacheStatus?.fetch >= App.time()-(pollTime-1)
		# There seems to be another master. Bail out.
		return
	fetch account, cacheStatus?.tweet

exports.handleTweets = (account,body) !->
	log 'body', body.substr(0,400)

	now = 0|App.time()
	cacheStatus = Db.origin.get("cache", account, "status") || {id:0}
	cacheStatus.fetch = now

	body = JSON.parse(body) || []
	newData = null
	for i in [body.length-1..0] by -1
		tweet = body[i]
		if tweet.id_str <= cacheStatus.tweet
			# the twitter api docs say this shouldn't happen, but it does (fixed now by using id_str instead of id? --Jelmer)
			continue
		log 'tweet', tweet.id_str, tweet.text
		cacheStatus.tweet = tweet.id_str
		post =
			time: 0 | ((new Date(tweet.created_at)).getTime()/1000)
			text: tweet.text
			tweet: tweet.id_str
		if (photo = tweet.entities?.media?[0]) and photo.type=="photo"
			post.photo = photo.media_url_https

		cacheStatus.id = 1 + (cacheStatus.id||0)
		Db.origin.set "cache", account, cacheStatus.id, post
		newData ||= {}
		newData[cacheStatus.id] = post

	Db.origin.set "cache", account, "status", cacheStatus

	if newData
		newData.status = cacheStatus
		newData.secret = pushSecret

	subs = Db.origin.get("cache", account, "subs") || {}
	cnt = 0
	for code,time of subs
		if time+subscribeTime > now
			# send to subscribed
			cnt++
			log "subscriber #{code}: " + JSON.stringify newData
			if newData
				Http.post
					url: "https://happening.im/x/#{code}"
					data: JSON.stringify newData
					name: false
		else
			log "unsubscribe #{code}"
			# unsubscribe
			Db.origin.set "cache", account, "subs", null

	if cnt
		log "set timer"
		Timer.set pollTime*1000, 'poll', account

exports.onHttp = (request) !->
	log 'onHttp '+request.data
	if (data = JSON.parse(request.data)) and data.secret==pushSecret
		delete data.secret
		Db.shared.merge data
		request.respond 'OK'

exports.client_remove = (id) !->
	return if App.userId() isnt Db.shared.get(id, 'by') and !App.userIsAdmin()

	# remove any associated photos
	Photo.remove photo if photo = Db.shared.get(id, 'photo')

	Db.shared.remove(id)

