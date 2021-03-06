Comments = require 'comments'
Db = require 'db'
Dom = require 'dom'
Event = require 'event'
Form = require 'form'
Icon = require 'icon'
Loglist = require 'loglist'
Modal = require 'modal'
Obs = require 'obs'
Page = require 'page'
Photo = require 'photo'
App = require 'app'
Server = require 'server'
Time = require 'time'
Ui = require 'ui'
Util = require 'util'
{tr} = require 'i18n'

exports.render = !->
	if postId = Page.state.get(0)
		renderSinglePost postId
	else
		renderWall()

renderSinglePost = (postId) !->
	Page.setTitle tr("Post")
	post = Db.shared.ref(postId)
	Event.showStar post.get('title')
	if App.userIsAdmin()
		Page.setActions
			icon: 'delete'
			action: !->
				Modal.confirm null, tr("Remove post?"), !->
					Server.sync 'remove', postId, !->
						Db.shared.remove(postId)
					Page.back()

	url = post.get('url')

	if !url and photoUrl = post.get('photo')
		Dom.style ChildMargin: '0'
		require('photoview').render
			url: photoUrl
	else if url
		Dom.div !->
			Dom.style
				Box: 'top'
				Flex: 1
				padding: '8px'
				margin: '8px 8px 4px 8px'
				backgroundColor: '#eee'
				border: '1px solid #ddd'
				borderBottom: '2px solid #ddd'
				borderRadius: '2px'
			Dom.cls 'link-box'

			if imgUrl = post.get('image')
				Dom.img !->
					Dom.style
						maxWidth: '120px'
						maxHeight: '200px'
						margin: '2px 8px 4px 2px'
					Dom.prop 'src', imgUrl

		Dom.div !->
			Dom.h3 !->
				Dom.style marginTop: 0
				Dom.text post.get('title')

			Dom.text post.get('description')

			Dom.div !->
				Dom.style
					marginTop: '6px'
					color: '#aaa'
					fontSize: '90%'
					whiteSpace: 'nowrap'
					textTransform: 'uppercase'
					fontWeight: 'normal'
				Dom.text Util.getDomainFromUrl(url)

		Dom.onTap !->
			App.openUrl url

	if text = post.get('text')
		Dom.div !->
			Dom.style padding: '8px 8px 0 8px' if (!url and photoUrl = post.get('photo'))
			Dom.userText text


	expanded = Obs.create false
	Dom.div !->
		Dom.style
			padding: '8px 8px 0 8px'
			fontSize: '85%'
			color: '#aaa'

		Dom.span !->
			Dom.style color: App.colors().highlight, padding: '5px 6px', margin: '-3px -3px -3px -6px'
			Icon.render
				data: 'twitter'
				size: 14
				color: App.colors().highlight
				style:
					margin: '2px 4px -2px 0'
			Dom.text tr("View tweet")
			Dom.onTap !->
				App.openUrl("https://twitter.com/#{Db.shared.get("cfg","account")}/status/#{post.get('tweet')}")
		Dom.text " • "

		Time.deltaText post.get('time')
		Dom.text " • "
		expanded = Comments.renderLike
			store: ["likes", postId+'-post']
			aboutWhat: tr("post")

	Obs.observe !->
		if expanded.get()
			Dom.div !->
				Dom.style margin: '0 8px 0 8px'
				Comments.renderLikeNames
					store: ["likes", postId+'-post']

	Comments.enable legacyStore: postId

	# Dom.div !->
	# 	Dom.style color: '#aaa', fontSize: '75%', margin: '2px 4px 4px 48px', textShadow: '0 1px 0 #fff', textAlign: 'right'
	# 	Dom.text tr("Messages are only visible in this happening")


renderWall = !->

	if !Db.shared.get("cfg","account")
		Dom.text "Not configured yet."
		return

	Obs.observe !->
		# Make sure we subscribe at least once every 5m when people are watching, 
		# but don't let all clients refresh the subscription at the same time.
		subscribed = (Db.shared.get("subscribed") || 0) + 2.00 + Math.random()*8.0
		if Obs.timePassed(subscribed)
			Server.sync "subscribe", !->
				Db.shared.set "subscribed", (0|App.time())

	Dom.style backgroundColor: '#f8f8f8'

	Obs.observe !->
		postCnt = 0
		empty = Obs.create(true)

		if fv = Page.state.get('firstV')
			firstV = Obs.create(fv)
		else
			firstV = Obs.create(-Math.max(1, (Db.shared.peek('status','id')||0)-20))
		lastV = Obs.create()
			# firstV and lastV are inversed when they go into Loglist
		Obs.observe !->
			lastV.set -(Db.shared.get('status','id')||0)

		# list of all posts
		Loglist.render lastV, firstV, (num) !->
			num = -num
			post = Db.shared.ref(num)
			return if !post.get('time')
			empty.set(!++postCnt)

			renderPost post

			Obs.onClean !->
				empty.set(!--postCnt)

		Dom.div !->
			if firstV.get()==-1
				Dom.style display: 'none'
				return
			Dom.style padding: '4px', textAlign: 'center'

			Ui.button tr("Earlier posts"), !->
				fv = Math.min(-1, firstV.peek()+20)
				firstV.set fv
				Page.state.set('firstV', fv)

		Obs.observe !->
			if empty.get()
				Ui.emptyText tr("Nothing has been posted yet"), 0, 0

renderPost = (post) !->
	Ui.item !->
		Dom.style Box: 'top'

		url = post.get('url')

		# main box showing content of the post
		Dom.div !->
			# header with name, time, likes, comments and unreadbubble
			Dom.div !->
				Dom.style Box: 'bottom', Flex: 1 ,margin: '4px 0'
				Icon.render
					data: 'twitter'
					size: 14
					color: '#56a7e1'
					style:
						margin: '-2px 4px 2px 0'
				Dom.div !->
					Dom.style color: '#aaa', fontSize: '85%'
					Dom.text " • "
					Time.deltaText post.get('time'), 'short'
					Dom.text " • "
					Comments.renderLike
						store: ["likes", post.key()+'-post']
						aboutWhat: tr("post")
						minimal: true

				Dom.div !->
					Dom.style Flex: 1, textAlign: 'right', paddingRight: '2px'

					likeCnt = 0
					likeCnt++ for k,v of Db.shared.get('likes', post.key()+'-post') when +k and v>0
					if likeCnt
						Dom.span !->
							Dom.style display: 'inline-block', fontSize: '85%', color: '#aaa'
							Icon.render
								data: 'thumbup'
								size: 16
								color: '#aaa'
								style: {verticalAlign: 'bottom', margin: '0 2px 1px 8px'}
							Dom.span likeCnt

					commentCnt = Db.shared.get('comments', post.key(), 'max')
					if commentCnt
						Dom.span !->
							Dom.style display: 'inline-block', fontSize: '85%', color: '#aaa'
							Icon.render
								data: 'comments'
								size: 16
								color: '#aaa'
								style: {verticalAlign: 'bottom', margin: '1px 2px 0 8px'}
							Dom.span commentCnt
					else
						Dom.span !->
							Dom.style fontSize: '85%', borderRadius: '2px', padding: '7px', margin: '-7px -4px -7px 3px', color: App.colors().highlight
							Dom.text tr("Reply")
							Dom.onTap !-> Page.nav [post.key()]

					# unread bubble
					Event.renderBubble [post.key()], style: margin: '-3px -6px -3px 8px'

			# post user text
			Dom.div !->
				Dom.cls 'user-text'
				Dom.userText post.get('text')||''


			# url or image attachment
			if url
				renderAttachedUrl post
			else if post.get 'photo'
				bgUrl = post.get 'photo'
				renderAttachedPhoto bgUrl

		Dom.onTap !->
			Page.nav post.key()



renderAttachedPhoto = (bgUrl, onTap) !->
	vpWidth = Page.width()
	vpHeight = Page.height()
	width = vpWidth
	if width * (1/2) > vpHeight * (1/2.5)
		height = 1/3 * vpHeight
		width = (2/1) * height

	Dom.div !->
		Dom.style maxWidth: width+'px'
		Dom.div !->
			Dom.style
				borderRadius: '2px'
				margin: if onTap then '0 0 8px 0' else '12px 0 8px 0'
				width: '100%'
				paddingBottom: '50%'
				backgroundImage: "url(#{bgUrl})"
				backgroundSize: 'cover'
				backgroundPosition: '50% 50%'
			if onTap
				Dom.onTap onTap

renderAttachedUrl = (post) !->
	Dom.div !->
		url = post.get 'url'
		Dom.cls 'link-box'
		Dom.style
			Box: true
			backgroundColor: '#eee'
			border: '1px solid #ddd'
			borderBottom: '2px solid #ddd'
			padding: '6px'
			borderRadius: '2px'
			margin: '12px 0 8px 0'
		if bgUrl = post.get 'image'
			Dom.div !->
				Dom.style
					borderRadius: '2px 0 0 2px'
					width: '50px'
					height: '50px'
					margin: '2px 7px 0 2px'
					backgroundImage: "url(#{bgUrl})"
					backgroundSize: 'cover'
					backgroundPosition: '50% 50%'

		Dom.div !->
			Dom.style Flex: 1, fontSize: '80%'

			Dom.div !->
				Dom.style textTransform: 'uppercase', color: '#888', fontWeight: 'bold'
				Dom.text post.get('title')
			Dom.div !->
				if descr = post.get('description')
					Dom.span !->
						Dom.text descr + ' '
				Dom.span !->
					Dom.style
						color: '#aaa'
						fontSize: '90%'
						whiteSpace: 'nowrap'
						textTransform: 'uppercase'
					Dom.text Util.getDomainFromUrl(url)

		Dom.onTap !->
			App.openUrl url

exports.renderSettings = !->

	if Db.shared
		Dom.div !-> Dom.text "It's not possible to change the Twitter account this plugin is showing. You could of course delete this plugin, and create a new instance."
		return

	cfg = Db.shared?.get('cfg') || {}

	Dom.div !->
		Dom.style Box: 'horizontal'
		Dom.div !->
			Dom.style
				fontSize: '21px'
				margin: '12px 4px 0 0'
			Dom.text "@"
		accountInput = Form.input
			name: "account"
			text: tr "Twitter account name"
			value: cfg.account
			onChange: (v) !->
				return if !v or !accountInput
				newV = v.replace(/[^a-zA-Z0-9_]/g, '')
				if v isnt newV
					accountInput.value newV
	Form.condition (val) ->
		tr("Account is required!") if !val.account

Dom.css
	'.link-box.tap':
		background: 'rgba(0, 0, 0, 0.1) !important'
	'.user-text A':
		color: '#aaa'
