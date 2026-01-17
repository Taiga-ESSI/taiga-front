###
# This source code is licensed under the terms of the
# GNU Affero General Public License found in the LICENSE file in
# the root directory of this source tree.
#
# Copyright (c) 2021-present Kaleidos INC
###

taiga = @.taiga
debounce = @.taiga.debounce

module = angular.module("taigaAuth", ["taigaResources"])

googleClientPromise = null

waitForGoogleClient = ($window) ->
    return googleClientPromise if googleClientPromise

    googleClientPromise = new Promise (resolve, reject) ->
        attempts = 0
        maxAttempts = 40
        delay = 250

        check = ->
            if $window.google? and $window.google.accounts? and $window.google.accounts.id?
                resolve($window.google.accounts.id)
            else if attempts >= maxAttempts
                reject(new Error("GOOGLE_CLIENT_TIMEOUT"))
            else
                attempts += 1
                $window.setTimeout(check, delay)

        check()

    return googleClientPromise


# Pol Alcoverro: helper para adjuntar el nuevo flujo de login con Google.
attachGoogleLogin = (options={}) ->
    scope = options.scope
    element = options.element
    auth = options.auth
    config = options.config
    confirm = options.confirm
    translate = options.translate
    $window = options.$window
    onSuccess = options.onSuccess
    onError = options.onError
    buildPayload = options.buildPayload
    loginType = options.loginType or "google"
    placeholderSelector = options.placeholderSelector or ".google-signin-placeholder"

    googleSettings = config.get("googleAuth") or {}
    enabled = Boolean(googleSettings.enabled and googleSettings.clientId)

    scope.googleAuthEnabled = enabled
    scope.googleLoading = false

    allowedDomains = googleSettings.allowedDomains or []
    formattedDomains = allowedDomains.map (domain) ->
        value = (domain or "").toString().trim()
        if value and value.charAt(0) == '@'
            return value
        return "@#{value}"

    formattedDomains = formattedDomains.filter (domain) -> domain.length > 1

    scope.googleAllowedDomains = formattedDomains

    domainsLabel = ""
    if formattedDomains.length > 0
        if formattedDomains.length == 1
            domainsLabel = formattedDomains[0]
        else
            head = formattedDomains.slice(0, formattedDomains.length - 1)
            tail = formattedDomains[formattedDomains.length - 1]
            orWord = translate.instant("COMMON.OR") or "or"
            if head.length == 1
                domainsLabel = "#{head[0]} #{orWord} #{tail}"
            else
                domainsLabel = "#{head.join(', ')} #{orWord} #{tail}"
    scope.googleDomainsLabel = domainsLabel

    return unless enabled

    buttonRendered = false

    onCredential = (googleResponse) ->
        credential = googleResponse?.credential
        return unless credential

        payload = null
        if buildPayload
            payload = buildPayload(credential, googleSettings) or {}
        else
            payload = {
                credential: credential
                client_id: googleSettings.clientId
            }

        payload.client_id ?= googleSettings.clientId

        scope.googleLoading = true
        scope.$applyAsync()

        auth.login(payload, loginType).then(onSuccess, (response) ->
            scope.googleLoading = false
            scope.$applyAsync()
            onError(response)
        )

    waitForGoogleClient($window).then (googleId) ->
        placeholder = element[0].querySelector(placeholderSelector)
        return unless placeholder
        return if buttonRendered

        googleId.initialize({
            client_id: googleSettings.clientId,
            callback: onCredential,
            cancel_on_tap_outside: true,
            auto_select: false
        })

        placeholder.innerHTML = ""
        googleId.renderButton(placeholder, {
            type: "standard",
            theme: "outline",
            size: "large",
            text: "signin_with",
            shape: "rectangular",
            logo_alignment: "center",
            width: 260,
            locale: translate.use() or "en"
        })

        buttonRendered = true
    , (err) ->
        scope.googleAuthEnabled = false
        scope.$applyAsync()
        confirm.notify("light-error", translate.instant("LOGIN_FORM.ERROR_GOOGLE_INIT"))

class LoginPage
    @.$inject = [
        '$scope',
        '$translate',
        'tgCurrentUserService',
        '$location',
        '$tgNavUrls',
        '$routeParams',
        '$tgAuth'
    ]

    constructor: ($scope, $translate, currentUserService, $location, $navUrls, $routeParams, $auth) ->
        $scope.getAccessProblemsUrl = ->
            lang = $translate.use()
            return "https://identitatdigital.upc.edu/gcredencials/?lang=#{lang}"

        if currentUserService.isAuthenticated()
            if not $routeParams['force_login']
                url = $navUrls.resolve("home")
                if $routeParams['next']
                    url = decodeURIComponent($routeParams['next'])
                    $location.search('next', null)

                if $routeParams['unauthorized']
                    $auth.clear()
                    $auth.removeToken()
                else
                    $location.url(url)


module.controller('LoginPage', LoginPage)

#############################################################################
## Authentication Service
#############################################################################

class AuthService extends taiga.Service
    @.$inject = ["$rootScope",
                 "$tgStorage",
                 "$tgModel",
                 "$tgResources",
                 "$tgHttp",
                 "$tgUrls",
                 "$tgConfig",
                 "$tgUserPilot",
                 "$translate",
                 "tgCurrentUserService",
                 "tgThemeService",
                 "$tgAnalytics"]

    constructor: (@rootscope, @storage, @model, @rs, @http, @urls, @config, @userpilot, @translate, @currentUserService,
                  @themeService, @analytics) ->
        super()

        userModel = @.getUser()
        @._currentTheme = @._getUserTheme()

        @.setUserdata(userModel)

    setUserdata: (userModel) ->
        if userModel
            @.userData = Immutable.fromJS(userModel.getAttrs())
            @currentUserService.setUser(@.userData)
        else
            @.userData = null
        @analytics.setUserId()

    _getUserTheme: ->
        compiledThemes = window._taigaAvailableThemes
        defaultTheme = @config.get("defaultTheme") || "taiga"

        if !_.includes(@config.get("themes"), @rootscope.user?.theme) || !compiledThemes.includes(@rootscope.user?.theme)
            return defaultTheme

        return @rootscope.user?.theme

    _setTheme: ->
        newTheme = @._getUserTheme()

        if @._currentTheme != newTheme
            @._currentTheme = newTheme
            @themeService.use(@._currentTheme)

    _setLocales: ->
        lang = @rootscope.user?.lang || @config.get("defaultLanguage") || "en"
        @translate.preferredLanguage(lang)  # Needed for calls to the api in the correct language
        @translate.use(lang)                # Needed for change the interface in runtime

    getUser: ->
        if @rootscope.user
            return @rootscope.user

        userData = @storage.get("userInfo")

        if userData
            user = @model.make_model("users", userData)
            @rootscope.user = user
            @._setLocales()

            @._setTheme()

            return user
        else
            @._setTheme()

        return null

    setUser: (user) ->
        @rootscope.auth = user
        @storage.set("userInfo", user.getAttrs())
        @rootscope.user = user

        @.setUserdata(user)

        @._setLocales()
        @._setTheme()

    clear: ->
        @rootscope.auth = null
        @rootscope.user = null
        @storage.remove("userInfo")

    setRefreshToken: (token) ->
        @storage.set("refresh", token)

    getRefreshToken: ->
        return @storage.get("refresh")

    setToken: (token) ->
        @storage.set("token", token)

    getToken: ->
        return @storage.get("token")

    removeToken: ->
        @storage.remove("token")
        @storage.remove("refresh")

    isAuthenticated: ->
        if @.getUser() != null
            return true
        return false

    ## Http interface
    refresh: () ->
        url = @urls.resolve("user-me")

        return @http.get(url).then (data, status) =>
            user = data.data
            user.token = @.getUser().auth_token

            user = @model.make_model("users", user)

            @.setUser(user)
            @rootscope.$broadcast("auth:refresh", user)
            return user

    login: (data, type) ->
        url = @urls.resolve("auth")

        data = _.clone(data, false)
        data.type = if type then type else "normal"

        @.removeToken()

        return @http.post(url, data).then (data, status) =>
            user = @model.make_model("users", data.data)
            @.setToken(user.auth_token)
            @.setRefreshToken(user.refresh)
            @.setUser(user)
            @rootscope.$broadcast("auth:login", user)
            return user

    logout: ->
        @.removeToken()
        @.clear()
        @currentUserService.removeUser()

        @._setTheme()
        @._setLocales()
        @rootscope.$broadcast("auth:logout")
        @analytics.setUserId()

    register: (data, type, existing) ->
        url = @urls.resolve("auth-register")

        data = _.clone(data, false)
        data.type = if type then type else "public"
        if type == "private"
            data.existing = if existing then existing else false

        @.removeToken()

        return @http.post(url, data).then (response) =>
            user = @model.make_model("users", response.data)
            @.setToken(user.auth_token)
            @.setUser(user)
            @rootscope.$broadcast("auth:register", user)
            return user

    getInvitation: (token) ->
        return @rs.invitations.get(token)

    acceptInvitiationWithNewUser: (data) ->
        return @.register(data, "private", false)

    forgotPassword: (data) ->
        url = @urls.resolve("users-password-recovery")
        data = _.clone(data, false)
        @.removeToken()
        return @http.post(url, data)

    changePasswordFromRecovery: (data) ->
        url = @urls.resolve("users-change-password-from-recovery")
        data = _.clone(data, false)
        @.removeToken()
        return @http.post(url, data)

    changeEmail: (data) ->
        url = @urls.resolve("users-change-email")
        data = _.clone(data, false)
        return @http.post(url, data)

    cancelAccount: (data) ->
        url = @urls.resolve("users-cancel-account")
        data = _.clone(data, false)
        return @http.post(url, data)

    exportProfile: () ->
        url = @urls.resolve("users-export")
        return @http.post(url)

    sendVerificationEmail: () ->
        url = @urls.resolve("user-send-verification-email")
        return @http.post(url)

module.service("$tgAuth", AuthService)


#############################################################################
## Login Directive
#############################################################################

# Directive that manages the visualization of public register
# message/link on login page.

PublicRegisterMessageDirective = ($config, $navUrls, $routeParams, templates) ->
    template = templates.get("auth/login-text.html", true)

    templateFn = ->
        publicRegisterEnabled = $config.get("publicRegisterEnabled")
        if not publicRegisterEnabled
            return ""

        url = $navUrls.resolve("login")

        if $routeParams['force_next']
            nextUrl = encodeURIComponent($routeParams['force_next'])
            url += "?next=#{nextUrl}"

        return template({url:url})

    return {
        restrict: "AE"
        scope: {}
        template: templateFn
    }

module.directive("tgPublicRegisterMessage", ["$tgConfig", "$tgNavUrls", "$routeParams",
                                             "$tgTemplate", PublicRegisterMessageDirective])


LoginDirective = ($auth, $confirm, $location, $config, $routeParams, $navUrls, $events, $translate, $window, $analytics) ->
    link = ($scope, $el, $attrs) ->
        ###
        # Pol Alcoverro: comentado codigo por deshabilitar el flujo de validacion del login clasico.
        # form = new checksley.Form($el.find("form.login-form"))
        ###
        $scope.defaultLoginEnabled = $config.get("defaultLoginEnabled", true)

        # ignore next param if is the login or discover page
        if $routeParams['next'] and $routeParams['next']  != $navUrls.resolve("login") and !$routeParams['next'].startsWith("%2Fdiscover")
            $scope.nextUrl = decodeURIComponent($routeParams['next'])
        else
            $scope.nextUrl = $navUrls.resolve("home")

        if $routeParams['force_next']
            $scope.nextUrl = decodeURIComponent($routeParams['force_next'])

        onSuccess = (response) ->
            $events.setupConnection()
            $analytics.trackEvent("auth", "login", "user login", 1)

            if $scope.nextUrl.indexOf('http') == 0
                $window.location.href = $scope.nextUrl
            else
                $location.url($scope.nextUrl)

        onError = (response) ->
            message = response?.data?._error_message or response?.data?.detail
            message = message or $translate.instant("LOGIN_FORM.ERROR_AUTH_INCORRECT")
            $confirm.notify("light-error", message)

        $scope.onKeyUp = (event) ->
            target = angular.element(event.currentTarget)
            value = target.val()
            $scope.iscapsLockActivated = false
            if value != value.toLowerCase()
                $scope.iscapsLockActivated = true

        ###
        # Pol Alcoverro: comentado codigo por deshabilitar el submit del login clasico.
        # submit = debounce 2000, (event) =>
        #     event.preventDefault()
        #
        #     if not form.validate()
        #         return
        #
        #     data = {
        #         "username": $el.find("form.login-form input[name=username]").val(),
        #         "password": $el.find("form.login-form input[name=password]").val()
        #     }
        #
        #     loginFormType = $config.get("loginFormType", "normal")
        #
        #     promise = $auth.login(data, loginFormType)
        #     return promise.then(onSuccess, onError)
        ###

        attachGoogleLogin({
            scope: $scope,
            element: $el,
            auth: $auth,
            config: $config,
            confirm: $confirm,
            translate: $translate,
            $window: $window,
            onSuccess: onSuccess,
            onError: onError
        })

        ###
        # Pol Alcoverro: comentado codigo por deshabilitar el binding del formulario clasico.
        # $el.on "submit", "form", submit
        ###

        window.prerenderReady = true

        $scope.changeLanguage = (lang) ->
            $translate.use(lang)

        $scope.$on "$destroy", ->
            $el.off()

    return {link:link}

module.directive("tgLogin", ["$tgAuth", "$tgConfirm", "$tgLocation", "$tgConfig", "$routeParams",
                             "$tgNavUrls", "$tgEvents", "$translate", "$window", "$tgAnalytics", LoginDirective])


#############################################################################
## Register Directive
#############################################################################

RegisterDirective = ($auth, $confirm, $location, $navUrls, $config, $routeParams, $analytics, $translate, $window) ->
    link = ($scope, $el, $attrs) ->
        if not $config.get("publicRegisterEnabled")
            $location.path($navUrls.resolve("not-found"))
            $location.replace()

        $scope.data = {}
        ###
        # Pol Alcoverro: comentado codigo por deshabilitar el flujo de validacion del registro clasico.
        # form = $el.find("form").checksley({onlyOneErrorElement: true})
        ###

        if $routeParams['next'] and $routeParams['next'] != $navUrls.resolve("login")
            $scope.nextUrl = decodeURIComponent($routeParams['next'])
        else
            $scope.nextUrl = $navUrls.resolve("home")

        onSuccessSubmit = (response) ->
            $analytics.trackEvent("auth", "register", "user registration", 1)

            if $scope.nextUrl.indexOf('http') == 0
                $window.location.href = $scope.nextUrl
            else
                $location.url($scope.nextUrl)

        onErrorSubmit = (response) ->
            if response.data._error_message
                text = $translate.instant("COMMON.GENERIC_ERROR", {error: response.data._error_message})
                $confirm.notify("light-error", text)

            ###
            # Pol Alcoverro: comentado codigo por deshabilitar el marcado de errores del registro clasico.
            # form.setErrors(response.data)
            ###

        ###
        # Pol Alcoverro: comentado codigo por deshabilitar el submit del registro clasico.
        # submit = debounce 2000, (event) =>
        #     event.preventDefault()
        #
        #     if not form.validate()
        #         return
        #
        #     promise = $auth.register($scope.data)
        #     promise.then(onSuccessSubmit, onErrorSubmit)
        ###

        ###
        # Pol Alcoverro: comentado codigo por deshabilitar el binding del registro clasico.
        # $el.on "submit", "form", submit
        ###

        $scope.$on "$destroy", ->
            $el.off()

        window.prerenderReady = true

    return {link:link}

module.directive("tgRegister", ["$tgAuth", "$tgConfirm", "$tgLocation", "$tgNavUrls", "$tgConfig",
                                "$routeParams", "$tgAnalytics", "$translate", "$window", RegisterDirective])


#############################################################################
## Register Options Directive
#############################################################################

RegisterOptionsDirective = () ->
    return { }

module.directive("tgRegisterOptions", [RegisterOptionsDirective])


#############################################################################
## Forgot Password Directive
#############################################################################

ForgotPasswordDirective = ($auth, $confirm, $location, $navUrls, $translate) ->
    link = ($scope, $el, $attrs) ->
        $scope.data = {}
        form = $el.find("form").checksley()

        onSuccessSubmit = (response) ->
            $location.path($navUrls.resolve("login"))

            title = $translate.instant("FORGOT_PASSWORD_FORM.SUCCESS_TITLE")
            message = $translate.instant("FORGOT_PASSWORD_FORM.SUCCESS_TEXT")

            $confirm.success(title, message)

        onErrorSubmit = (response) ->
            text = $translate.instant("FORGOT_PASSWORD_FORM.ERROR")

            $confirm.notify("light-error", text)

        submit = debounce 2000, (event) =>
            event.preventDefault()

            if not form.validate()
                return

            promise = $auth.forgotPassword($scope.data)
            promise.then(onSuccessSubmit, onErrorSubmit)

        $el.on "submit", "form", submit

        $scope.$on "$destroy", ->
            $el.off()

        window.prerenderReady = true

    return {link:link}

module.directive("tgForgotPassword", ["$tgAuth", "$tgConfirm", "$tgLocation", "$tgNavUrls", "$translate",
                                      ForgotPasswordDirective])


#############################################################################
## Change Password from Recovery Directive
#############################################################################

ChangePasswordFromRecoveryDirective = ($auth, $confirm, $location, $params, $navUrls, $translate) ->
    link = ($scope, $el, $attrs) ->
        $scope.data = {}

        if $params.token?
            $scope.tokenInParams = true
            $scope.data.token = $params.token
        else
            $location.path($navUrls.resolve("login"))

            text = ''
            text = response.data.token.map((message) ->
                return "#{text} #{message}"
            )
            $confirm.notify("light-error", text)

        form = $el.find("form").checksley()

        onSuccessSubmit = (response) ->
            $location.path($navUrls.resolve("login"))

            text = $translate.instant("CHANGE_PASSWORD_RECOVERY_FORM.SUCCESS")
            $confirm.success(text)

        onErrorSubmit = (response) ->
            text = ''
            text = response.data.password.map((message) ->
                return "#{text} #{message}"
            )
            $confirm.notify("light-error", text)

        submit = debounce 2000, (event) =>
            event.preventDefault()

            if not form.validate()
                return

            promise = $auth.changePasswordFromRecovery($scope.data)
            promise.then(onSuccessSubmit, onErrorSubmit)

        $el.on "submit", "form", submit

        $scope.$on "$destroy", ->
            $el.off()

    return {link:link}

module.directive("tgChangePasswordFromRecovery", ["$tgAuth", "$tgConfirm", "$tgLocation", "$routeParams",
                                                  "$tgNavUrls", "$translate",
                                                  ChangePasswordFromRecoveryDirective])


#############################################################################
## Invitation
#############################################################################

InvitationDirective = ($auth, $confirm, $location, $config, $params, $navUrls, $analytics, $translate, $window, config) ->
    link = ($scope, $el, $attrs) ->
        token = $params.token

        promise = $auth.getInvitation(token)
        promise.then (invitation) ->
            $scope.invitation = invitation
            $scope.publicRegisterEnabled = config.get("publicRegisterEnabled")

        promise.then null, (response) ->
            $location.path($navUrls.resolve("login"))

            text = $translate.instant("INVITATION_LOGIN_FORM.NOT_FOUND")
            $confirm.notify("light-error", text)

        # Login form
        $scope.dataLogin = {token: token}
        ###
        # Pol Alcoverro: comentado codigo por deshabilitar la validacion del login clasico en invitaciones.
        # loginForm = $el.find("form.login-form").checksley({onlyOneErrorElement: true})
        ###

        onSuccessSubmitLogin = (response) ->
            $analytics.trackEvent("auth", "invitationAccept", "invitation accept with existing user", 1)
            $location.path($navUrls.resolve("project", {project: $scope.invitation.project_slug}))
            text = $translate.instant("INVITATION_LOGIN_FORM.SUCCESS", {
                "project_name": $scope.invitation.project_name
            })

            $confirm.notify("success", text)

        onErrorSubmitLogin = (response) ->
            message = response?.data?._error_message or response?.data?.detail
            message = message or $translate.instant("LOGIN_FORM.ERROR_AUTH_INCORRECT")
            $confirm.notify("light-error", message)

        ###
        # Pol Alcoverro: comentado codigo por deshabilitar el submit del login clasico en invitaciones.
        # submitLogin = debounce 2000, (event) =>
        #     event.preventDefault()
        #
        #     if not loginForm.validate()
        #         return
        #
        #     loginFormType = $config.get("loginFormType", "normal")
        #     data = $scope.dataLogin
        #
        #     promise = $auth.login({
        #         username: data.username,
        #         password: data.password,
        #         invitation_token: data.token
        #     }, loginFormType)
        #     promise.then(onSuccessSubmitLogin, onErrorSubmitLogin)
        ###

        ###
        # Pol Alcoverro: comentado codigo por deshabilitar el binding del login clasico en invitaciones.
        # $el.on "submit", "form.login-form", submitLogin
        # $el.on "click", ".button-login", submitLogin
        ###

        attachGoogleLogin({
            scope: $scope,
            element: $el,
            auth: $auth,
            config: $config,
            confirm: $confirm,
            translate: $translate,
            $window: $window,
            onSuccess: onSuccessSubmitLogin,
            onError: onErrorSubmitLogin,
            buildPayload: (credential, googleSettings) ->
                {
                    credential: credential
                    client_id: googleSettings.clientId
                    invitation_token: token
                }
        })

        # Register form
        $scope.dataRegister = {token: token}
        ###
        # Pol Alcoverro: comentado codigo por deshabilitar la validacion del registro clasico en invitaciones.
        # registerForm = $el.find("form.register-form").checksley({onlyOneErrorElement: true})
        ###

        onSuccessSubmitRegister = (response) ->
            $analytics.trackEvent("auth", "invitationAccept", "invitation accept with new user", 1)

            $location.path($navUrls.resolve("project", {project: $scope.invitation.project_slug}))
            text = $translate.instant("INVITATION_LOGIN_FORM.SUCCESS", {
                "project_name": $scope.invitation.project_name
            })
            $confirm.notify("success", text)

        onErrorSubmitRegister = (response) ->
            if response.data._error_message
                text = $translate.instant("COMMON.GENERIC_ERROR", {error: response.data._error_message})
                $confirm.notify("light-error", text)

            ###
            # Pol Alcoverro: comentado codigo por deshabilitar el marcado de errores del registro clasico en invitaciones.
            # registerForm.setErrors(response.data)
            ###

        ###
        # Pol Alcoverro: comentado codigo por deshabilitar el submit del registro clasico en invitaciones.
        # submitRegister = debounce 2000, (event) =>
        #     event.preventDefault()
        #
        #     if not registerForm.validate()
        #         return
        #
        #     promise = $auth.acceptInvitiationWithNewUser($scope.dataRegister)
        #     promise.then(onSuccessSubmitRegister, onErrorSubmitRegister)
        ###

        ###
        # Pol Alcoverro: comentado codigo por deshabilitar el binding del registro clasico en invitaciones.
        # $el.on "submit", "form.register-form", submitRegister
        # $el.on "click", ".button-register", submitRegister
        ###

        $scope.$on "$destroy", ->
            $el.off()

    return {link:link}

module.directive("tgInvitation", ["$tgAuth", "$tgConfirm", "$tgLocation", "$tgConfig", "$routeParams",
                                  "$tgNavUrls", "$tgAnalytics", "$translate", "$window", "$tgConfig", InvitationDirective])


#############################################################################
## Verify Email
#############################################################################

VerifyEmailDirective = ($repo, $model, $auth, $confirm, $location, $params, $navUrls, $translate) ->
    link = ($scope, $el, $attrs) ->
        $scope.data = {}
        $scope.data.email_token = $params.email_token
        form = $el.find("form").checksley()

        onSuccessSubmit = (response) ->
            if $auth.isAuthenticated()
                $repo.queryOne("users", $auth.getUser().id).then (data) =>
                    $auth.setUser(data)
                $location.url($navUrls.resolve("home"))
            else
                $location.url($navUrls.resolve("login"))

            text = $translate.instant("VERIFY_EMAIL_FORM.SUCCESS")
            $confirm.success(text)

        onErrorSubmit = (response) ->
            text = $translate.instant("COMMON.GENERIC_ERROR", {error: response.data._error_message})

            $confirm.notify("light-error", text)

        submit = ->
            if not form.validate()
                return

            promise = $auth.changeEmail($scope.data)
            promise.then(onSuccessSubmit, onErrorSubmit)

        $el.on "submit", (event) ->
            event.preventDefault()
            submit()

        $el.on "click", "a.ng-submit-form", (event) ->
            event.preventDefault()
            submit()

        $scope.$on "$destroy", ->
            $el.off()

    return {link:link}

module.directive("tgVerifyEmail", ["$tgRepo", "$tgModel", "$tgAuth", "$tgConfirm", "$tgLocation",
                                   "$routeParams", "$tgNavUrls", "$translate", VerifyEmailDirective])


#############################################################################
## Change Email
#############################################################################

ChangeEmailDirective = ($repo, $model, $auth, $confirm, $location, $params, $navUrls, $translate) ->
    link = ($scope, $el, $attrs) ->
        $scope.data = {}
        $scope.data.email_token = $params.email_token
        form = $el.find("form").checksley()

        onSuccessSubmit = (response) ->
            if $auth.isAuthenticated()
                $repo.queryOne("users", $auth.getUser().id).then (data) =>
                    $auth.setUser(data)
                $location.url($navUrls.resolve("home"))
            else
                $location.url($navUrls.resolve("login"))

            text = $translate.instant("CHANGE_EMAIL_FORM.SUCCESS")
            $confirm.success(text)

        onErrorSubmit = (response) ->
            text = $translate.instant("COMMON.GENERIC_ERROR", {error: response.data._error_message})

            $confirm.notify("light-error", text)

        submit = ->
            if not form.validate()
                return

            promise = $auth.changeEmail($scope.data)
            promise.then(onSuccessSubmit, onErrorSubmit)

        $el.on "submit", (event) ->
            event.preventDefault()
            submit()

        $el.on "click", "a.ng-submit-form", (event) ->
            event.preventDefault()
            submit()

        $scope.$on "$destroy", ->
            $el.off()

    return {link:link}

module.directive("tgChangeEmail", ["$tgRepo", "$tgModel", "$tgAuth", "$tgConfirm", "$tgLocation",
                                   "$routeParams", "$tgNavUrls", "$translate", ChangeEmailDirective])


#############################################################################
## Cancel account
#############################################################################

CancelAccountDirective = ($repo, $model, $auth, $confirm, $location, $params, $navUrls) ->
    link = ($scope, $el, $attrs) ->
        $scope.data = {}
        $scope.data.cancel_token = $params.cancel_token
        form = $el.find("form").checksley()

        onSuccessSubmit = (response) ->
            $auth.logout()
            $location.path($navUrls.resolve("home"))

            text = $translate.instant("CANCEL_ACCOUNT.SUCCESS")

            $confirm.success(text)

        onErrorSubmit = (response) ->
            text = $translate.instant("COMMON.GENERIC_ERROR", {error: response.data._error_message})

            $confirm.notify("error", text)

        submit = debounce 2000, (event) =>
            event.preventDefault()

            if not form.validate()
                return

            promise = $auth.cancelAccount($scope.data)
            promise.then(onSuccessSubmit, onErrorSubmit)

        $el.on "submit", "form", submit

        $scope.$on "$destroy", ->
            $el.off()

    return {link:link}

module.directive("tgCancelAccount", ["$tgRepo", "$tgModel", "$tgAuth", "$tgConfirm", "$tgLocation",
                                     "$routeParams","$tgNavUrls", CancelAccountDirective])
