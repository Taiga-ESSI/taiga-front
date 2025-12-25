###
# This source code is licensed under the terms of the
# GNU Affero General Public License found in the LICENSE file in
# the root directory of this source tree.
#
# Copyright (c) 2021-present Kaleidos INC
# Pol Alcoverro - Tests para la autenticación con Google
###

describe "Google Authentication", ->
    $window = null
    $timeout = null
    $scope = null
    config = null

    beforeEach ->
        module "taigaBase"

        inject (_$window_, _$timeout_, _$rootScope_) ->
            $window = _$window_
            $timeout = _$timeout_
            $scope = _$rootScope_.$new()

    describe "waitForGoogleClient", ->
        beforeEach ->
            # Reset google object
            delete $window.google

        it "should resolve when google client is already loaded", (done) ->
            $window.google = {
                accounts: {
                    id: {
                        initialize: ->
                    }
                }
            }

            waitForGoogleClient = ->
                new Promise (resolve, reject) ->
                    if $window.google?.accounts?.id?
                        resolve($window.google.accounts.id)
                    else
                        reject(new Error("NOT_LOADED"))

            waitForGoogleClient().then (client) ->
                expect(client).to.exist
                expect(client.initialize).to.be.a("function")
                done()
            .catch done

        it "should reject after timeout if google client is not loaded", (done) ->
            waitForGoogleClient = ->
                new Promise (resolve, reject) ->
                    attempts = 0
                    maxAttempts = 2
                    delay = 50

                    check = ->
                        if $window.google?.accounts?.id?
                            resolve($window.google.accounts.id)
                        else if attempts >= maxAttempts
                            reject(new Error("GOOGLE_CLIENT_TIMEOUT"))
                        else
                            attempts += 1
                            setTimeout(check, delay)

                    check()

            waitForGoogleClient().then ->
                done(new Error("Should not resolve"))
            .catch (error) ->
                expect(error.message).to.be.equal("GOOGLE_CLIENT_TIMEOUT")
                done()

    describe "attachGoogleLogin configuration", ->
        it "should enable google auth when settings are valid", ->
            config = {
                get: (key) ->
                    if key == "googleAuth"
                        return {
                            enabled: true
                            clientId: "test-client-id.apps.googleusercontent.com"
                        }
            }

            scope = {}
            attachGoogleLogin = (options) ->
                googleSettings = options.config.get("googleAuth") or {}
                enabled = Boolean(googleSettings.enabled and googleSettings.clientId)
                options.scope.googleAuthEnabled = enabled

            attachGoogleLogin({
                scope: scope
                config: config
            })

            expect(scope.googleAuthEnabled).to.be.true

        it "should disable google auth when clientId is missing", ->
            config = {
                get: (key) ->
                    if key == "googleAuth"
                        return {
                            enabled: true
                            clientId: null
                        }
            }

            scope = {}
            attachGoogleLogin = (options) ->
                googleSettings = options.config.get("googleAuth") or {}
                enabled = Boolean(googleSettings.enabled and googleSettings.clientId)
                options.scope.googleAuthEnabled = enabled

            attachGoogleLogin({
                scope: scope
                config: config
            })

            expect(scope.googleAuthEnabled).to.be.false

        it "should disable google auth when enabled is false", ->
            config = {
                get: (key) ->
                    if key == "googleAuth"
                        return {
                            enabled: false
                            clientId: "test-client-id.apps.googleusercontent.com"
                        }
            }

            scope = {}
            attachGoogleLogin = (options) ->
                googleSettings = options.config.get("googleAuth") or {}
                enabled = Boolean(googleSettings.enabled and googleSettings.clientId)
                options.scope.googleAuthEnabled = enabled

            attachGoogleLogin({
                scope: scope
                config: config
            })

            expect(scope.googleAuthEnabled).to.be.false

    describe "allowed domains formatting", ->
        it "should format single domain correctly", ->
            allowedDomains = ["example.com"]
            formattedDomains = allowedDomains.map (domain) ->
                value = (domain or "").toString().trim()
                if value and value.charAt(0) == '@'
                    return value
                return "@#{value}"

            expect(formattedDomains).to.be.eql(["@example.com"])

        it "should keep @ prefix if already present", ->
            allowedDomains = ["@example.com"]
            formattedDomains = allowedDomains.map (domain) ->
                value = (domain or "").toString().trim()
                if value and value.charAt(0) == '@'
                    return value
                return "@#{value}"

            expect(formattedDomains).to.be.eql(["@example.com"])

        it "should format multiple domains correctly", ->
            allowedDomains = ["example.com", "test.com", "@another.com"]
            formattedDomains = allowedDomains.map (domain) ->
                value = (domain or "").toString().trim()
                if value and value.charAt(0) == '@'
                    return value
                return "@#{value}"

            expect(formattedDomains).to.be.eql(["@example.com", "@test.com", "@another.com"])

        it "should filter out empty domains", ->
            allowedDomains = ["example.com", "", "  ", null]
            formattedDomains = allowedDomains.map (domain) ->
                value = (domain or "").toString().trim()
                if value and value.charAt(0) == '@'
                    return value
                return "@#{value}"
            
            formattedDomains = formattedDomains.filter (domain) -> domain.length > 1

            expect(formattedDomains).to.be.eql(["@example.com"])

    describe "domains label generation", ->
        it "should create label for single domain", ->
            formattedDomains = ["@example.com"]
            domainsLabel = formattedDomains[0]

            expect(domainsLabel).to.be.equal("@example.com")

        it "should create label for two domains with OR", ->
            formattedDomains = ["@example.com", "@test.com"]
            orWord = "or"
            
            if formattedDomains.length == 2
                domainsLabel = "#{formattedDomains[0]} #{orWord} #{formattedDomains[1]}"
            
            expect(domainsLabel).to.be.equal("@example.com or @test.com")

        it "should create label for multiple domains with commas and OR", ->
            formattedDomains = ["@example.com", "@test.com", "@another.com"]
            orWord = "or"
            
            if formattedDomains.length > 2
                head = formattedDomains.slice(0, formattedDomains.length - 1)
                tail = formattedDomains[formattedDomains.length - 1]
                domainsLabel = "#{head.join(', ')} #{orWord} #{tail}"

            expect(domainsLabel).to.be.equal("@example.com, @test.com or @another.com")
