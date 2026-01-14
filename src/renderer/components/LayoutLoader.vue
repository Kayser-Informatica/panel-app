<script>
  import auth from '@/store/modules/auth'
  import { log } from '@/util/functions'

  let eventSource = null
  let running = false
  let timeoutId = 0
  let pollingInterval = null
  let usePolling = false

  // this funciton is needed because computed value is not being updated
  function isExpired ($store) {
    return auth.getters.isExpired($store.state.auth)
  }

  function doConnect ($root, $store, attempts) {
    if (attempts <= 0) {
      log('Max connection attempts reached. Falling back to polling mode.')
      startPolling($root, $store)
      return
    }
    $store.dispatch('fetchApiInfo').then(() => {
      disconnect()

      let mercureUrl = $store.state.apiInfo.mercureUrl || ''
      log('Mercure URL from API: ' + mercureUrl)
  
      if (!mercureUrl.toLowerCase().startsWith('http')) {
        let serverUrl = $store.state.config.server
        if (!serverUrl.endsWith('/')) {
          serverUrl += '/'
        }
        if (mercureUrl.startsWith('/')) {
          mercureUrl = serverUrl + mercureUrl.substring(1)
        } else {
          mercureUrl = serverUrl + mercureUrl
        }
      }

      // Fix common URL issues: ensure we use the correct Mercure endpoint
      // The correct endpoint is /.well-known/mercure, not /mercure
      try {
        const urlObj = new URL(mercureUrl)
        const pathname = urlObj.pathname
  
        // If path is /mercure or just /, change to /.well-known/mercure
        if (pathname === '/mercure' || pathname === '/' || pathname === '') {
          urlObj.pathname = '/.well-known/mercure'
          mercureUrl = urlObj.toString()
          log('Fixed Mercure URL to use correct endpoint: ' + mercureUrl)
        } else if (!pathname.includes('.well-known/mercure')) {
          // If path doesn't contain .well-known/mercure, append it
          urlObj.pathname = '/.well-known/mercure'
          mercureUrl = urlObj.toString()
          log('Fixed Mercure URL to use correct endpoint: ' + mercureUrl)
        }
      } catch (e) {
        log('Error parsing Mercure URL, using as-is: ' + e.message)
      }

      log('Final Mercure URL: ' + mercureUrl)

      const url = new URL(mercureUrl)
      url.searchParams.append('topic', `/unidades/${$store.state.config.unity}/painel`)
  
      log('Connecting to EventSource: ' + url.toString())
  
      try {
        eventSource = new EventSource(url)
  
        eventSource.onopen = (e) => {
          log('EventSource connection opened successfully')
          stopPolling() // Stop polling if EventSource works
        }
  
        eventSource.onmessage = (e) => {
          log('EventSource message received')
          fetchMessages($root, $store)
        }
  
        eventSource.onerror = (e) => {
          log('EventSource error occurred. ReadyState: ' + eventSource.readyState)
  
          // Check if we can get more info about the error
          // EventSource doesn't expose HTTP status directly, but we can infer from readyState
          if (eventSource.readyState === EventSource.CLOSED) {
            log('EventSource connection closed. This might indicate a server error (e.g., 502 Bad Gateway).')
            log('The Mercure server at ' + url.toString() + ' is not responding correctly.')
            log('Falling back to polling mode immediately.')
  
            disconnect()
            // For 502 errors, immediately fall back to polling instead of retrying
            startPolling($root, $store)
  
            // Still try to reconnect in background, but don't block on it
            setTimeout(() => {
              if (!usePolling || attempts > 0) {
                log('Attempting to reconnect EventSource in background...')
                doConnect($root, $store, attempts - 1)
              }
            }, 5000)
          } else if (eventSource.readyState === EventSource.CONNECTING) {
            // Still connecting, wait a bit more
            log('EventSource still connecting...')
          } else if (eventSource.readyState === EventSource.OPEN) {
            // Connection is open but error occurred - might be temporary
            log('EventSource is open but error occurred - might be temporary network issue')
          }
        }
      } catch (error) {
        log('Error creating EventSource: ' + error.message)
        $root.$swal('Erro de Conexão', 'Não foi possível conectar ao servidor de eventos. Verifique se a URL do Mercure está acessível publicamente.', 'error')
        setTimeout(() => {
          doConnect($root, $store, attempts - 1)
        }, 5000)
      }
    }).catch((e) => {
      log('Error fetching API info: ' + e)
      clearToken($root, $store).then(() => {
        doConnect($root, $store, attempts - 1)
      })
    })

    // initial fetch
    fetchMessages($root, $store)
  }

  function clearToken ($root, $store) {
    // clear token
    $store.commit('updateToken', {})
    return doCheckToken($root, $store)
  }

  function doCheckToken ($root, $store) {
    return new Promise((resolve, reject) => {
      let promise = Promise.resolve()
      if ($store.getters.isAuthenticated && isExpired($store)) {
        log('token expired, refreshing')
        promise = $store
          .dispatch('refresh')
          .then(() => {
            log('token refreshed successfully!')
            return Promise.resolve()
          })
          .catch((error) => {
            log('error on refresh token: ' + error)
            log('trying to issue a new token')
            return $store.dispatch('token')
          })
      } else if (!$store.getters.isAuthenticated) {
        log('not authenticated, issuing new token')
        promise = $store
          .dispatch('token')
          .then(() => {
            log('token issued successfully!')
            return Promise.resolve()
          })
          .catch((error) => {
            log('error on issuing token')
            return Promise.reject(error)
          })
      }
      promise.then(resolve).catch((error) => {
        log('error on issuing/refresh token. go to settings!')
        $root.$swal('Oops!', error, 'error')
        $root.$router.push('/settings')
      })
    })
  }

  function connect ($root, $store) {
    if (!$store.state.config || !$store.state.config.server) {
      log('panel no configured yet. go to settings!')
      $root.$router.push('/settings')
      return
    }

    doConnect($root, $store, 3)
  }

  function disconnect () {
    if (eventSource) {
      eventSource.close()
      eventSource = null
    }
    stopPolling()
  }

  function startPolling ($root, $store) {
    if (usePolling || pollingInterval) {
      return
    }
    usePolling = true
    log('Starting polling mode as fallback (checking every 3 seconds)')
    pollingInterval = setInterval(() => {
      fetchMessages($root, $store)
    }, 3000)
  }

  function stopPolling () {
    if (pollingInterval) {
      clearInterval(pollingInterval)
      pollingInterval = null
      usePolling = false
      log('Stopped polling mode')
    }
  }

  function checkToken ($root, $store) {
    clearTimeout(timeoutId)

    if (!running) {
      log('not running')
      return
    }

    log('checking token. Authenticated: ' + $store.getters.isAuthenticated + '. isExpired: ' + isExpired($store))
    doCheckToken($root, $store)

    timeoutId = setTimeout(() => {
      checkToken($root, $store)
    }, 60 * 1000)
  }

  function fetchMessages ($root, $store) {
    if (!running) {
      running = true
      checkToken($root, $store)
    }
    $store
      .dispatch('fetchMessages')
      .catch(e => {
        log('Error getting messages: ' + e)
        clearToken($root, $store)
      })
  }

  export default {
    name: 'Layout',

    render (h) {
      let view
      try {
        const theme = this.$store.getters.theme
        view = require(`@/layouts/${theme}`).default
      } catch (e) {
        view = require('@/layouts/novosga.default').default
      }
      return h(view)
    },

    beforeMount () {
      connect(this, this.$store)
    },

    beforeDestroy () {
      running = false
      disconnect()
      stopPolling()
      clearTimeout(timeoutId)
    }
  }
</script>
