set-variable -name itgWebRedirectionServicePostfix -value "web.inet.services.novgaro.ru" -option constant
set-variable -name itgWebRedirectionIISServer -value "web.inet.services.novgaro.ru" -option constant

set-variable -name itgDNSServer -value "server-v2.novgaro.ru" -scope global
set-variable -name itgDNSZone -value "novgaro.ru" -scope global

function New-WebRedirection {
	<#
		.Synopsis
		    Создаёт приложение IIS (web site), целью которого является совместно с правилом web публикации на ISA обеспечить
            перенаправление http запросов на "основной" web сервер (www.<domain>)
		.Description
		    Создаёт приложение IIS (web site), целью которого является совместно с правилом web публикации на ISA обеспечить
            перенаправление http запросов на "основной" web сервер (www.<domain>). Для домена novgaro.com будет создан сайт
            novgaro-com.web.inet.services.novgaro.ru, файловый ресурс которого будет создан в папке physicalRoot. Данный сайт
            на все получаемые http запросы будет отвечать постоянной ошибкой - ресурс переехал на www.novgaro.com.
            При этом сервис будет размещён на порту port и будет отвечать на host header novgaro-com.web.inet.services.novgaro.ru.
            
            При этом также будет предпринята попытка создания необходимых dns записей.
		.Parameter domain
		    Домен, для которого требуется создать сервис перенаправления http запросов. Будет создан web сервис, который будет 
            все http запросы перенаправлять на url www.<domain>.
		.Parameter port
			Порт, на котором будем активировать сервис. Если не указан - 80.
		.Parameter physicalRoot
			Папка, в которой будет создан файловый ресурс для сервиса.
		.Parameter applicationPool
			Пул приложений IIS, в котором будет создан сервис.
		.Example
			Создание группы сервисов:
			"rtsauto.ru","garotrade.ru" | New-WebRedirection
	#>
	
    
    param (
		[Parameter(
			Mandatory=$true,
			Position=0,
			ValueFromPipeline=$true,
			HelpMessage="Домен, для которого требуется создать сервис перенаправления http запросов."
		)]
        [string]$domain,
		[Parameter(
			Mandatory=$false,
			Position=1,
			ValueFromPipeline=$false,
			HelpMessage="Порт, на котором будем активировать сервис."
		)]
        [int]$port = 80,
		[Parameter(
			Mandatory=$false,
			Position=2,
			ValueFromPipeline=$false,
			HelpMessage="Папка, в которой будет создан файловый ресурс для сервиса."
		)]
  		[string]$physicalRoot = "${env:systemdrive}\inetpub\redirecting",
		[Parameter(
			Mandatory=$false,
			Position=3,
			ValueFromPipeline=$false,
			HelpMessage="Пул приложений IIS, в котором будет создан сервис."
		)]
		[string]$applicationPool = "WEB sites redirecting"
	)
	PROCESS {
		[string]$hostHeaderPrefix = $domain.replace( ".", "-")
		[string]$webServiceName = "${hostHeaderPrefix}.${itgWebRedirectionServicePostfix}"
		[string]$physicalPath = "${physicalRoot}\${webServiceName}"
        
        # регистрация записей в dns
        # The text version of the record. Must include Class (IN) or this will fail.  
        # @ represents the origin, or zone / domain name.  
        $DNSRecordAsText = "${webServiceName} IN CNAME ${itgWebRedirectionIISServer}." 
        $DNSRRClass = [WMIClass]"\\$itgDNSServer\root\MicrosoftDNS:MicrosoftDNS_ResourceRecord" 
        $DNSRecord = $DNSRRClass.CreateInstanceFromTextRepresentation($itgDNSServer, $itgDNSZone, $DNSRecordAsText)
        
        # создание web сервиса
        
        if ([System.IO.Directory]::Exists("${physicalPath}") -eq $false) {
	  		new-item "${physicalPath}" -type Directory
		}
        
		$site = new-item "IIS:\Sites\${webServiceName}" `
			-physicalPath "${physicalPath}" `
			-bindings `
				@{protocol="http";bindingInformation="*:${port}:${webServiceName}"} `
			-applicationPool $applicationPool `
            -force
		$site.enabledProtocols = "http"
		$site.limits.maxBandwidth = 1024
		$site.limits.maxConnections = 100
		$site.serverAutoStart = $true
		set-webConfiguration `
			-psPath "IIS:\Sites\${webServiceName}" `
			-filter "system.webServer/httpRedirect" `
			-value @{ `
				enabled="true";`
				destination="http://www.${domain}/";`
				exactDestination="false";`
				childOnly="false";`
				httpResponseStatus="Permanent"`
			} `
			-force
		set-webConfiguration `
			-psPath "IIS:\Sites\${webServiceName}" `
			-filter "system.webServer/caching" `
			-value @{ `
				enabled="false";`
				enableKernelCache="false"`
			} `
			-force
		$site.Start()
        write-output $site
	}
}  

function Remove-WebRedirection {
	<#
		.Synopsis
		    Удаляет приложение IIS (web site), целью которого является совместно с правилом web публикации на ISA обеспечить
            перенаправление http запросов на "основной" web сервер (www.<domain>)
		.Description
		    Удаляет приложение IIS (web site), целью которого является совместно с правилом web публикации на ISA обеспечить
            перенаправление http запросов на "основной" web сервер (www.<domain>). Например для домена novgaro.com был создан сайт
            novgaro-com.web.inet.services.novgaro.ru, файловый ресурс которого будет создан в папке physicalRoot. Данный сайт
            на все получаемые http запросы отвечал постоянной ошибкой - ресурс переехал на www.novgaro.com.
            При этом сервис будет размещён на порту port и будет отвечать на host header novgaro-com.web.inet.services.novgaro.ru.
		.Parameter domain
		    Домен, для которого требуется удалить сервис перенаправления http запросов.
		.Example
			Создание группы сервисов:
			"rtsauto.ru","garotrade.ru" | Remove-WebRedirection
	#>
	
    
    param (
		[Parameter(
			Mandatory=$true,
			Position=0,
			ValueFromPipeline=$true,
			HelpMessage="Домен, для которого требуется удалить сервис перенаправления http запросов."
		)]
        [string]$domain
	)
	PROCESS {
		[string]$hostHeaderPrefix = $domain.replace( ".", "-")
		[string]$webServiceName = "${hostHeaderPrefix}.${itgWebRedirectionServicePostfix}"
        
        remove-webSite $webServiceName
	}
}  

Export-ModuleMember "New-WebRedirection","Remove-WebRedirection"
