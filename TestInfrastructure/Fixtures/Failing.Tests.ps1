Describe 'Intentional failure fixture' {
    It 'fails so build failure propagation can be verified' {
        $true | Should -BeFalse
    }
}
