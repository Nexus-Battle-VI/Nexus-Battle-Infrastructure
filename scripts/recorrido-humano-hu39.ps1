<#
.SYNOPSIS
Carga ayudantes interactivos para verificar HU-39 contra producción sin
imprimir contraseñas, testimonios ni códigos TOTP.

.DESCRIPTION
Se debe cargar con dot-sourcing:

    . 'D:\Desarrollo\Proyectos\UPB\Nexus-Battle\Nexus-Battle-Infrastructure\scripts\recorrido-humano-hu39.ps1'

Las credenciales se solicitan interactivamente. Los access tokens permanecen
en memoria dentro de los objetos de sesión y se eliminan con
Clear-NexusHu39Secrets al terminar.
#>

$script:NexusHu39BaseUri = 'https://nexus.simuladorupbbga.app'

function Read-NexusSecretText {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    $secure = Read-Host $Prompt -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)

    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Invoke-NexusRequest {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Path,

        [AllowNull()]
        [string]$Token = $null,

        [AllowNull()]
        [object]$Body = $null
    )

    $request = @{
        Uri                = "$script:NexusHu39BaseUri$Path"
        Method             = $Method
        SkipHttpErrorCheck = $true
        UseBasicParsing    = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $request.Headers = @{ Authorization = "Bearer $Token" }
    }

    if ($null -ne $Body) {
        $request.ContentType = 'application/json'
        $request.Body = $Body | ConvertTo-Json -Compress -Depth 8
    }

    $response = Invoke-WebRequest @request
    $data = $null

    if (-not [string]::IsNullOrWhiteSpace($response.Content)) {
        try {
            $data = $response.Content | ConvertFrom-Json
        }
        catch {
            $data = $response.Content
        }
    }

    [pscustomobject]@{
        Status = [int]$response.StatusCode
        Data   = $data
    }
}

function New-NexusSession {
    param(
        [Parameter(Mandatory)]
        [string]$Label
    )

    $identifier = Read-Host "$Label - correo o apodo"
    $password = Read-NexusSecretText "$Label - contraseña"

    try {
        $step = Invoke-NexusRequest -Method POST -Path '/api/sessions' -Body @{
            identifier = $identifier
            password   = $password
        }
    }
    finally {
        $password = $null
    }

    if ($step.Status -ne 200) {
        throw "${Label}: el inicio de sesión respondió HTTP $($step.Status)."
    }

    if ($step.Data.status -eq 'SECOND_FACTOR_SELECTION_REQUIRED') {
        $step = Invoke-NexusRequest -Method POST -Path '/api/sessions/second-factor/method' -Body @{
            identifier     = $identifier
            challengeToken = $step.Data.challengeToken
            method         = 'AUTHENTICATOR_APP'
        }
    }

    if ($step.Data.status -eq 'SECOND_FACTOR_REQUIRED') {
        $code = Read-NexusSecretText "$Label - código TOTP"

        try {
            $step = Invoke-NexusRequest -Method POST -Path '/api/sessions/second-factor' -Body @{
                identifier     = $identifier
                challengeToken = $step.Data.challengeToken
                code           = $code
            }
        }
        finally {
            $code = $null
        }
    }

    if ($step.Status -ne 200 -or $step.Data.status -ne 'AUTHENTICATED') {
        throw "${Label}: la autenticación no terminó correctamente."
    }

    [pscustomobject]@{
        Token      = $step.Data.accessToken
        AccountId  = $step.Data.account.id
        Roles      = @($step.Data.account.roles)
        ExpiresIn  = $step.Data.expiresIn
        Identifier = $identifier
    }
}

function Test-NexusUnauthenticated {
    $search = Invoke-NexusRequest -Method GET -Path '/api/accounts/search?email=probe%40example.invalid'
    $assign = Invoke-NexusRequest -Method POST -Path '/api/accounts/00000000-0000-4000-8000-000000000000/roles' -Body @{
        role = 'MODERATOR'
    }

    $result = [pscustomobject]@{
        SearchWithoutToken = $search.Status
        AssignWithoutToken = $assign.Status
        Passed             = $search.Status -eq 401 -and $assign.Status -eq 401
    }

    $result

    if (-not $result.Passed) {
        throw 'El control sin testimonio no devolvió 401 en ambas rutas.'
    }
}

function Test-NexusRoleManagementForbidden {
    param(
        [Parameter(Mandatory)]
        [object]$Session,

        [Parameter(Mandatory)]
        [string]$ExpectedLabel
    )

    $response = Invoke-NexusRequest -Method POST -Path '/api/accounts/00000000-0000-4000-8000-000000000000/roles' -Token $Session.Token -Body @{
        role = 'MODERATOR'
    }

    $result = [pscustomobject]@{
        Actor  = $ExpectedLabel
        Status = $response.Status
        Passed = $response.Status -eq 403
    }

    $result

    if (-not $result.Passed) {
        throw "$ExpectedLabel debía recibir 403 y recibió $($response.Status)."
    }
}

function Find-NexusManagedAccount {
    param(
        [Parameter(Mandatory)]
        [object]$SuperSession,

        [Parameter(Mandatory)]
        [string]$Email
    )

    $encoded = [Uri]::EscapeDataString($Email.Trim())
    $response = Invoke-NexusRequest -Method GET -Path "/api/accounts/search?email=$encoded" -Token $SuperSession.Token

    if ($response.Status -ne 200) {
        throw "La búsqueda de la cuenta respondió HTTP $($response.Status)."
    }

    $response.Data
}

function Test-NexusMfaPrecondition {
    param(
        [Parameter(Mandatory)]
        [object]$SuperSession,

        [Parameter(Mandatory)]
        [object]$TargetAccount
    )

    if ($TargetAccount.mfaEnrolled) {
        throw 'La cuenta ya tiene TOTP. Use una cuenta PLAYER sin TOTP para probar el 409.'
    }

    $response = Invoke-NexusRequest -Method POST -Path "/api/accounts/$($TargetAccount.id)/roles" -Token $SuperSession.Token -Body @{
        role = 'ADMINISTRATOR'
    }

    if ($response.Status -eq 200) {
        $rollback = Invoke-NexusRequest -Method DELETE -Path "/api/accounts/$($TargetAccount.id)/roles/ADMINISTRATOR" -Token $SuperSession.Token
        throw "FALLO DE SEGURIDAD: se concedió ADMINISTRATOR sin TOTP. Rollback HTTP $($rollback.Status)."
    }

    $result = [pscustomobject]@{
        AssignAdministratorWithoutTotp = $response.Status
        Passed                         = $response.Status -eq 409
    }

    $result

    if (-not $result.Passed) {
        throw "Se esperaba 409 y se recibió $($response.Status)."
    }
}

function Test-NexusAdministratorAccess {
    param(
        [Parameter(Mandatory)]
        [object]$AdminSession
    )

    if ($AdminSession.Roles -notcontains 'ADMINISTRATOR') {
        throw 'El testimonio nuevo no contiene ADMINISTRATOR.'
    }

    $account = Invoke-NexusRequest -Method GET -Path "/api/accounts/$($AdminSession.AccountId)" -Token $AdminSession.Token
    $roles = Invoke-NexusRequest -Method POST -Path '/api/accounts/00000000-0000-4000-8000-000000000000/roles' -Token $AdminSession.Token -Body @{
        role = 'MODERATOR'
    }

    $result = [pscustomobject]@{
        AccountAdministratorRoute = $account.Status
        RoleManagement            = $roles.Status
        Passed                    = $account.Status -eq 200 -and $roles.Status -eq 403
    }

    $result

    if (-not $result.Passed) {
        throw 'Se esperaba 200 en Account y 403 al gestionar roles.'
    }
}

function Test-NexusCatalogLifecycle {
    param(
        [Parameter(Mandatory)]
        [object]$AdminSession
    )

    $sku = "hu39-e2e-$([DateTimeOffset]::UtcNow.ToString('yyyyMMddHHmmss'))"
    $created = $false
    $createStatus = $null
    $publishStatus = $null
    $archiveStatus = $null

    try {
        $create = Invoke-NexusRequest -Method POST -Path '/api/products' -Token $AdminSession.Token -Body @{
            sku           = $sku
            name          = 'Producto técnico HU-39'
            category      = 'hu39-e2e'
            priceAmount   = 1
            priceCurrency = 'COP'
        }
        $createStatus = $create.Status
        $created = $create.Status -eq 201

        if (-not $created) {
            throw "La creación del producto respondió HTTP $createStatus."
        }

        $publish = Invoke-NexusRequest -Method POST -Path "/api/products/$sku/publication" -Token $AdminSession.Token
        $publishStatus = $publish.Status

        if ($publish.Status -ne 200) {
            throw "La publicación del producto respondió HTTP $publishStatus."
        }
    }
    finally {
        if ($created) {
            $archive = Invoke-NexusRequest -Method POST -Path "/api/products/$sku/archival" -Token $AdminSession.Token
            $archiveStatus = $archive.Status
        }
    }

    $result = [pscustomobject]@{
        Sku     = $sku
        Create  = $createStatus
        Publish = $publishStatus
        Archive = $archiveStatus
        Passed  = $createStatus -eq 201 -and $publishStatus -eq 200 -and $archiveStatus -eq 200
    }

    $result

    if (-not $result.Passed) {
        throw 'El ciclo de Catalog no terminó con 201/200/200.'
    }
}

function Test-NexusOldTokenAfterRevoke {
    param(
        [Parameter(Mandatory)]
        [object]$OldAdminSession
    )

    $response = Invoke-NexusRequest -Method POST -Path '/api/products' -Token $OldAdminSession.Token -Body @{}

    [pscustomobject]@{
        OldTokenAfterRevoke = $response.Status
        Interpretation      = if ($response.Status -eq 400) {
            'Token anterior todavía autorizado; la validación rechazó el cuerpo vacío y no escribió.'
        }
        elseif ($response.Status -in @(401, 403)) {
            'Privilegio denegado inmediatamente.'
        }
        else {
            'Resultado inesperado; detener y revisar.'
        }
    }
}

function Test-NexusAfterRevoke {
    param(
        [Parameter(Mandatory)]
        [object]$NewSession
    )

    if ($NewSession.Roles -contains 'ADMINISTRATOR') {
        throw 'El testimonio nuevo todavía contiene ADMINISTRATOR.'
    }

    $account = Invoke-NexusRequest -Method GET -Path "/api/accounts/$($NewSession.AccountId)" -Token $NewSession.Token
    $catalog = Invoke-NexusRequest -Method POST -Path '/api/products' -Token $NewSession.Token -Body @{}
    $roles = Invoke-NexusRequest -Method POST -Path '/api/accounts/00000000-0000-4000-8000-000000000000/roles' -Token $NewSession.Token -Body @{
        role = 'MODERATOR'
    }

    $result = [pscustomobject]@{
        AccountAdministratorRoute = $account.Status
        CatalogManagement         = $catalog.Status
        RoleManagement            = $roles.Status
        Passed                    = $account.Status -eq 403 -and $catalog.Status -eq 403 -and $roles.Status -eq 403
    }

    $result

    if (-not $result.Passed) {
        throw 'El testimonio nuevo debía recibir 403/403/403.'
    }
}

function Clear-NexusHu39Secrets {
    Remove-Variable player, super, admin, afterRevoke, moderator, finalPlayer -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable target, targetEmail -Scope Global -ErrorAction SilentlyContinue
    [GC]::Collect()
    Clear-History
    Write-Host 'Variables de sesión e historial eliminados. Cierre esta consola.'
}

Write-Host 'Ayudantes HU-39 cargados desde archivo local.'
Write-Host 'Destino: https://nexus.simuladorupbbga.app'
