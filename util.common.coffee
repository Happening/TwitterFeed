exports.getDomainFromUrl = (url) ->
	# TODO: improve (e.g. news.bbc.co.uk)
	url.match(/(^https?:\/\/)?([^\/]+)/)[2].split('.').slice(-2).join('.')

exports.getUrlsFromText = (text) ->
	urls = []
	text
		.replace /([^\w\/]|^)www\./ig, '$1http://www.'
		.replace /\bhttps?:\/\/([a-z0-9\.\-]+\.[a-z]+)([/:][^\s\)'",<]*)?/ig, (url) ->
			if url[-1..] in ['.','!','?']
				# dropping the ? is questionable
				url = url[0...-1]
			urls.push url
	urls
