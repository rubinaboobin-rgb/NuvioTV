@file:OptIn(ExperimentalTvMaterial3Api::class)

package com.nuvio.tv.ui.screens.account

import com.nuvio.tv.ui.theme.NuvioTheme

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.tv.material3.Button
import androidx.tv.material3.ButtonDefaults
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import androidx.compose.ui.res.stringResource
import com.nuvio.tv.R
import com.nuvio.tv.domain.model.AuthState

@Composable
fun AuthSignInScreen(
    onBackPress: () -> Unit = {},
    onSuccess: () -> Unit = {},
    viewModel: AccountViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    val canSubmit = email.isNotBlank() && password.isNotBlank() && !uiState.isLoading

    LaunchedEffect(uiState.authState) {
        if (uiState.authState is AuthState.FullAccount) {
            onSuccess()
        }
    }

    BackHandler { onBackPress() }

    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth(0.5f)
                .background(
                    color = NuvioTheme.colors.BackgroundElevated,
                    shape = RoundedCornerShape(20.dp)
                )
                .padding(NuvioTheme.spacing.xxl),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = stringResource(R.string.auth_signin_title),
                style = MaterialTheme.typography.headlineSmall,
                color = NuvioTheme.colors.TextPrimary,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(10.dp))
            Text(
                text = stringResource(R.string.auth_signin_email_password_desc),
                style = MaterialTheme.typography.bodyMedium,
                color = NuvioTheme.colors.TextSecondary,
                textAlign = TextAlign.Center
            )
            if (uiState.debugBackendSwitchEnabled) {
                Spacer(modifier = Modifier.height(18.dp))
                DebugSyncBackendSwitchCard(
                    uiState = uiState,
                    requireConfirmation = false,
                    onSwitchBackend = viewModel::switchDebugBackend
                )
            }
            Spacer(modifier = Modifier.height(22.dp))

            InputField(
                value = email,
                onValueChange = { email = it },
                placeholder = stringResource(R.string.auth_signin_email_placeholder),
                keyboardType = KeyboardType.Email,
                imeAction = ImeAction.Next
            )
            Spacer(modifier = Modifier.height(12.dp))
            InputField(
                value = password,
                onValueChange = { password = it },
                placeholder = stringResource(R.string.auth_signin_password_placeholder),
                keyboardType = KeyboardType.Password,
                isPassword = true,
                imeAction = ImeAction.Done,
                onImeAction = {
                    if (canSubmit) {
                        viewModel.signIn(email.trim(), password)
                    }
                }
            )

            if (!uiState.error.isNullOrBlank()) {
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = uiState.error!!,
                    style = MaterialTheme.typography.bodySmall,
                    color = NuvioTheme.colors.Error,
                    textAlign = TextAlign.Center
                )
            }

            Spacer(modifier = Modifier.height(18.dp))
            Button(
                onClick = { viewModel.signIn(email.trim(), password) },
                enabled = canSubmit,
                colors = ButtonDefaults.colors(
                    containerColor = NuvioTheme.colors.Secondary,
                    focusedContainerColor = NuvioTheme.colors.SecondaryVariant,
                    contentColor = NuvioTheme.colors.OnSecondary,
                    focusedContentColor = NuvioTheme.colors.OnSecondaryVariant,
                    disabledContainerColor = NuvioTheme.colors.BackgroundCard
                ),
                shape = ButtonDefaults.shape(RoundedCornerShape(50)),
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = if (uiState.isLoading) stringResource(R.string.auth_signin_working) else stringResource(R.string.auth_signin_button),
                    modifier = Modifier.padding(vertical = NuvioTheme.spacing.xs),
                    fontWeight = FontWeight.Medium
                )
            }

            Spacer(modifier = Modifier.height(10.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Button(
                    onClick = { viewModel.signUp(email.trim(), password) },
                    enabled = canSubmit,
                    colors = ButtonDefaults.colors(
                        containerColor = NuvioTheme.colors.BackgroundCard,
                        focusedContainerColor = NuvioTheme.colors.FocusBackground,
                        contentColor = NuvioTheme.colors.TextPrimary,
                        focusedContentColor = NuvioTheme.colors.TextPrimary,
                        disabledContainerColor = NuvioTheme.colors.BackgroundCard.copy(alpha = 0.55f)
                    ),
                    shape = ButtonDefaults.shape(RoundedCornerShape(50)),
                    modifier = Modifier.weight(1f)
                ) {
                    Text(
                        text = stringResource(R.string.auth_signin_create_button),
                        modifier = Modifier.padding(vertical = NuvioTheme.spacing.xs),
                        fontWeight = FontWeight.Medium
                    )
                }
                Button(
                    onClick = onBackPress,
                    enabled = !uiState.isLoading,
                    colors = ButtonDefaults.colors(
                        containerColor = NuvioTheme.colors.BackgroundCard,
                        focusedContainerColor = NuvioTheme.colors.FocusBackground,
                        contentColor = NuvioTheme.colors.TextPrimary,
                        focusedContentColor = NuvioTheme.colors.TextPrimary
                    ),
                    shape = ButtonDefaults.shape(RoundedCornerShape(50)),
                    modifier = Modifier.weight(1f)
                ) {
                    Text(
                        text = stringResource(R.string.auth_signin_back_button),
                        modifier = Modifier.padding(vertical = NuvioTheme.spacing.xs),
                        fontWeight = FontWeight.Medium
                    )
                }
            }
        }
    }
}
