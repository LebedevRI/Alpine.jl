function brainpc3(; solver = nothing)
    m = JuMP.Model(solver)

    # ----- Variables ----- #
    @variable(m, x[1:6907])

    @NLobjective(
        m,
        Min,
        (
            (-0.003214) + x[16] - (x[16] + x[3467]) * x[6903] +
            x[3467] +
            6.34e-6 * x[6903]
        )^2 +
        (x[46] - (x[46] + x[3497]) * x[6903] + x[3497] + 0.01551 * x[6903])^2 +
        (x[76] - (x[76] + x[3527]) * x[6903] + x[3527] + 0.008919 * x[6903])^2 +
        (x[106] - (x[106] + x[3557]) * x[6903] + x[3557] + 0.005968 * x[6903])^2 +
        (x[136] - (x[136] + x[3587]) * x[6903] + x[3587] + 0.005773 * x[6903])^2 +
        (x[166] - (x[166] + x[3617]) * x[6903] + x[3617] + 0.004985 * x[6903])^2 +
        (x[196] - (x[196] + x[3647]) * x[6903] + x[3647] + 0.004795 * x[6903])^2 +
        (x[226] - (x[226] + x[3677]) * x[6903] + x[3677] + 0.004409 * x[6903])^2 +
        (x[271] - (x[271] + x[3722]) * x[6903] + x[3722] + 0.003829 * x[6903])^2 +
        (x[331] - (x[331] + x[3782]) * x[6903] + x[3782] + 0.003269 * x[6903])^2 +
        (x[391] - (x[391] + x[3842]) * x[6903] + x[3842] + 0.00317 * x[6903])^2 +
        (x[451] - (x[451] + x[3902]) * x[6903] + x[3902] + 0.00307 * x[6903])^2 +
        (x[511] - (x[511] + x[3962]) * x[6903] + x[3962] + 0.002971 * x[6903])^2 +
        (x[631] - (x[631] + x[4082]) * x[6903] + x[4082] + 0.002765 * x[6903])^2 +
        (x[811] - (x[811] + x[4262]) * x[6903] + x[4262] + 0.00247 * x[6903])^2 +
        (x[991] - (x[991] + x[4442]) * x[6903] + x[4442] + 0.002252 * x[6903])^2 +
        (x[1171] - (x[1171] + x[4622]) * x[6903] + x[4622] + 0.002066 * x[6903])^2 +
        (x[1351] - (x[1351] + x[4802]) * x[6903] + x[4802] + 0.001891 * x[6903])^2 +
        (x[1531] - (x[1531] + x[4982]) * x[6903] + x[4982] + 0.00173 * x[6903])^2 +
        (x[1711] - (x[1711] + x[5162]) * x[6903] + x[5162] + 0.001713 * x[6903])^2 +
        (x[1951] - (x[1951] + x[5402]) * x[6903] + x[5402] + 0.00166 * x[6903])^2 +
        (x[2251] - (x[2251] + x[5702]) * x[6903] + x[5702] + 0.001548 * x[6903])^2 +
        (x[2551] - (x[2551] + x[6002]) * x[6903] + x[6002] + 0.001435 * x[6903])^2 +
        (x[2851] - (x[2851] + x[6302]) * x[6903] + x[6302] + 0.001323 * x[6903])^2 +
        (x[3151] - (x[3151] + x[6602]) * x[6903] + x[6602] + 0.00121 * x[6903])^2 +
        (x[3451] - (x[3451] + x[6902]) * x[6903] + x[6902] + 0.001098 * x[6903])^2
    )

    return m  # model get returned when including this script.
end
