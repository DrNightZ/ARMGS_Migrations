# Здесь необходимо задать куки авторизационной сессии администратора.
# Для получения куков надо залогиниться в Firefox на https://biz.armgs.team , 
# зайти в инструменты разработчика нажав F12 и перейти в раздел "Хранилище"
# Нужны значения для трех элементов: Mpop, sdcs и csrftoken
$Mpop = "XXXXXXX";
$sdcs = "YYYYYYY";
$csrftoken = "ZZZZZZZ";
           
#******* START ********#


$Базовый_Адрес = "biz.armgs.team";
$Макс_Страница = 100;
$Адрес_АПИ =  "https://$Базовый_Адрес/api";
$Таймаут_АнтиДДОС = 100;		# В Миллисекундах, интервал между операциями
$ТаймаутСистемы = 5;				# В секундах, время системе на подумать ))




function Получить-АПИОтвет ($адрес) {
	$Ответ = Invoke-WebRequest $адрес  -ContentType 'application/json' -WebSession $Сессия
	$Содержимое = КонвертацияИзISOВUtf8($Ответ.Content)

	$Содержимое | ConvertFrom-Json
}


function Получить-ДоменыАРМГС {	
	Получить-АПИОтвет "$Адрес_АПИ/domains"
}

function Получить-СтатусыМиграции ($domain_id) {
	$Статусы = $null;
	$Сдвиг = 0;

	do {
		$Данные =  $(Получить-АПИОтвет "$Адрес_АПИ/domains/$domain_id/collectors?limit=$Макс_Страница&offset=$Сдвиг").data
		
		$Сдвиг += $Макс_Страница
		$Статусы += $Данные
		
	} while ($Данные.Count -gt 0)
	
	return $Статусы;	
}


function КонвертацияИзISOВUtf8([string] $Строка) {
    [System.Text.Encoding]::UTF8.GetString(
        [System.Text.Encoding]::GetEncoding(28591).GetBytes($Строка)
    )
}


$Сессия = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$Кук = New-Object System.Net.Cookie('Mpop',$Mpop,'/', $Базовый_Адрес)
$Сессия.Cookies.Add($Кук)
$Кук = New-Object  System.Net.Cookie('sdcs',$sdcs,'/',$Базовый_Адрес)
$Сессия.Cookies.Add($Кук)
$Кук = New-Object  System.Net.Cookie('csrftoken',$csrftoken,'/',$Базовый_Адрес)
$Сессия.Cookies.Add($Кук)



# Выбираем домен
$Домен = $(Получить-ДоменыАРМГС ) | select name, id, migration, created_at | Out-GridView -Title "Выберите нужный домен" -PassThru 


if($Домен -ne $null){
	$СтатусыМиграции = Получить-СтатусыМиграции $Домен.id	
	
	if($Учётка -eq $null) {
		$Учётка = Get-Credential -Message "Учетная запись с полным доступом к почтовым ящикам в виде DOMAIN\username"   
	}

	# Статус 1 - миграция работает, убираем
	$СтатусыМиграции | ? {$_.status -ne 1} | % {
		$ЭлектроПочта = $_.email
		$Домен_Аутентификации = $Учётка.GetNetworkCredential().domain
		$Имя_Админского_Пользователя = $Учётка.GetNetworkCredential().username
		$Имя_Почтового_Пользователя = @($ЭлектроПочта.Split("@"))[0]
		
		$PUTПараметры = @{passwd = $Учётка.GetNetworkCredential().password; username = "$Домен_Аутентификации/$Имя_Админского_Пользователя/$Имя_Почтового_Пользователя"} | ConvertTo-Json

		$МетодAPI = 'PUT'

		# В случае, если сборщика вообще еще нет используем метод POST
		if($_.status -eq 0) {
			$МетодAPI = 'POST'
		}

		try {
			$Ответ = Invoke-RestMethod -Uri "$Адрес_АПИ/domains/$($Домен.id)/collectors/$($_.id)" -WebSession $Сессия -Method $МетодAPI -ContentType 'application/json' -Body $PUTПараметры -Headers @{
				'Referer' = $Адрес_АПИ;
				'X-CSRFToken' = $csrftoken;	
				}
		} catch {
			Write-Host "Не удалось включить для адреса $ЭлектроПочта"
			
		}
		
			# На всякий случай, что бы не забанили
		Start-Sleep -Milliseconds $Таймаут_АнтиДДОС 

	}

	Start-Sleep -Seconds $ТаймаутСистемы

	$СтатусыМиграции = Получить-СтатусыМиграции $Домен.id	
	
	$Успешные_Количество = $($СтатусыМиграции | ? {$_.status -eq 1}).count
	$Все_Количество = $СтатусыМиграции.count
	
	Write-Host "Всего $Все_Количество пользователей, успешно миграция работает у $Успешные_Количество"

}



