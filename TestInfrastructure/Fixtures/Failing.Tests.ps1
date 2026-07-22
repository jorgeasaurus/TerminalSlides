Describe 'Intentional build failure fixture' {
    It 'fails so the build failure gate can be verified' {
        $true | Should -BeFalse
    }
}
