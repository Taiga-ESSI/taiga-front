###
# Sergio Utrilla added - Instructor module
# Descripción: Punto de entrada del módulo de instructor. Declara el módulo taigaInstructor
#              y registra las URLs de la API academics en $tgUrls.
###

module = angular.module("taigaInstructor", [])

init = ($log, $tgUrls) ->
    $log.debug "Initialize taigaInstructor URLs"
    $tgUrls.update({
        "academics-subjects":               "academics/subjects"
        "academics-editions":               "academics/course-editions"
        "academics-edition-dashboard":      "academics/course-editions/%s/dashboard"
        "academics-metrics-policies":       "academics/metrics-policies"
        "academics-metrics-policy-detail":  "academics/metrics-policies/%s"
    })

module.run(["$log", "$tgUrls", init])
