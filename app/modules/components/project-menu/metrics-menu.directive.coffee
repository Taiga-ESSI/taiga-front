###
# This source code is licensed under the terms of the
# GNU Affero General Public License found in the LICENSE file in
# the root directory of this source tree.
#
# Copyright (c) 2021-present Kaleidos
###

# Modificado, añadido por Pol Alcoverro
angular.module("taigaComponents").directive "tgMetricsMenu", [
    "$document",
    "$timeout",
    "$translate",
    ($document, $timeout, $translate) ->
        link = (scope, element) ->
            navElement = null
            metricsItem = null
            originalLink = null
            toggleButton = null
            childMenu = null
            documentHandler = null
            mutationObserver = null

            translations = {
                team: $translate.instant("METRICS.TEAM_METRICS_TITLE")
                project: $translate.instant("METRICS.PROJECT_METRICS_TITLE")
            }

            navCollapsed = ->
                return navElement?.classList.contains("collapsed")

            closeMenu = ->
                return unless metricsItem && childMenu
                metricsItem.classList.remove("metrics-open")
                childMenu.style.display = "none"

            openMenu = ->
                return unless metricsItem && childMenu
                metricsItem.classList.add("metrics-open")
                childMenu.style.display = "block"

            toggleMenu = ->
                return unless metricsItem && childMenu
                if metricsItem.classList.contains("metrics-open")
                    closeMenu()
                else
                    openMenu()

            buildChevron = ->
                svgNS = "http://www.w3.org/2000/svg"
                svg = document.createElementNS(svgNS, "svg")
                svg.setAttribute("class", "agile-chevron")
                svg.setAttribute("data-animation", "text")
                use = document.createElementNS(svgNS, "use")
                use.setAttributeNS("http://www.w3.org/1999/xlink", "href", "#chevron-left")
                svg.appendChild(use)
                return svg

            buildChildLink = (kind, href) ->
                li = document.createElement("li")
                li.className = "menu-option"

                anchor = document.createElement("a")
                anchor.setAttribute("href", href)
                anchor.className = "metrics-submenu-link"
                anchor.textContent = translations[kind]
                anchor.addEventListener "click", ->
                    closeMenu()

                li.appendChild(anchor)
                return li

            buildChildMenu = ->
                templateLink = originalLink.getAttribute("href") or ""
                projectHref = templateLink.replace(/\/team(\/)?$/, "/project$1")
                if projectHref == templateLink
                    projectHref = templateLink + "/project"

                childMenu = document.createElement("ul")
                childMenu.className = "child-menu metrics-child-menu"
                childMenu.style.display = "none"
                childMenu.appendChild(buildChildLink("team", templateLink))
                childMenu.appendChild(buildChildLink("project", projectHref))
                metricsItem.appendChild(childMenu)

            enhanceMetricsItem = ->
                return if metricsItem?.classList.contains("metrics-enhanced")
                return unless metricsItem

                metricsItem.classList.add("metrics-has-dropdown", "metrics-enhanced")
                originalLink = metricsItem.querySelector("a")
                return unless originalLink

                toggleButton = document.createElement("button")
                toggleButton.type = "button"
                toggleButton.className = "menu-option-button"
                toggleButton.innerHTML = originalLink.innerHTML
                toggleButton.appendChild(buildChevron())

                originalLink.setAttribute("aria-hidden", "true")
                originalLink.setAttribute("tabindex", "-1")
                originalLink.classList.add("metrics-hidden-link")
                originalLink.style.display = "none"

                metricsItem.insertBefore(toggleButton, originalLink)
                buildChildMenu()

                toggleButton.addEventListener "click", (event) ->
                    if navCollapsed()
                        return
                    event.preventDefault()
                    event.stopPropagation()
                    toggleMenu()

                documentHandler = (event) ->
                    return unless metricsItem?.classList.contains("metrics-open")
                    return if metricsItem.contains(event.target)
                    closeMenu()

                $document.on("click", documentHandler)

            observeNavigation = ->
                return unless navElement
                mutationObserver = new MutationObserver (mutations) ->
                    for mutation in mutations when mutation.attributeName == "class"
                        closeMenu() if navCollapsed()

                mutationObserver.observe(navElement, {
                    attributes: true
                    attributeFilter: ["class"]
                })

            locateMetricsItem = ->
                iconSelector = 'use[href="#icon-metrics"], use[xlink\\:href="#icon-metrics"], use[href="#icon-graph"], use[xlink\\:href="#icon-graph"]'
                icon = navElement?.querySelector(iconSelector)
                metricsItem = icon?.closest("li")
                if metricsItem
                    enhanceMetricsItem()

            setup = ->
                navElement = element[0].querySelector("tg-project-navigation")
                if !navElement
                    $timeout(setup, 100)
                    return
                locateMetricsItem()
                observeNavigation()

            setup()

            scope.$on "$destroy", ->
                closeMenu()
                if documentHandler
                    $document.off("click", documentHandler)
                mutationObserver?.disconnect()

        {
            restrict: "A"
            link: link
        }
]
