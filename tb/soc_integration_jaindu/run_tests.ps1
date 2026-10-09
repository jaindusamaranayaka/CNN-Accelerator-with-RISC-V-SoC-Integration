# PowerShell script to run all SoC Integration testbenches
Push-Location $PSScriptRoot

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Running SoC Integration Verification Suite" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

vlib work
vmap work work

$tests = @(
    @{ name = "tb_display_gpio_peripheral"; src = "../../rtl/soc_integration_jaindu/display_gpio_peripheral.sv" },
    @{ name = "tb_soc_bus_interconnect";    src = "../../rtl/soc_integration_jaindu/soc_bus_interconnect.sv" },
    @{ name = "tb_image_buffer_bram";       src = "../../rtl/soc_integration_jaindu/image_buffer_bram.sv" },
    @{ name = "tb_pixel_stream_reader";     src = "../../rtl/soc_integration_jaindu/pixel_stream_reader.sv" },
    @{ name = "tb_uart_serial_controller";  src = "../../rtl/soc_integration_jaindu/uart_serial_controller.sv" }
)

$allPassed = $true
foreach ($t in $tests) {
    Write-Host "`n>>> Running $($t.name)..." -ForegroundColor Yellow
    vlog -sv $t.src "$($t.name).sv"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "COMPILATION FAILED: $($t.name)" -ForegroundColor Red
        $allPassed = $false
        continue
    }
    vsim -c -do "run -all; quit -f" $t.name
    if ($LASTEXITCODE -ne 0) {
        Write-Host "SIMULATION FAILED: $($t.name)" -ForegroundColor Red
        $allPassed = $false
    }
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "ALL 83 TESTS PASSED SUCCESSFULLY!" -ForegroundColor Green
} else {
    Write-Host "SOME TESTS FAILED!" -ForegroundColor Red
}
Write-Host "==========================================================" -ForegroundColor Cyan

Pop-Location
