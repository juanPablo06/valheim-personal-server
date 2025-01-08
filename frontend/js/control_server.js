const poolData = {
	UserPoolId: process.env.COGNITO_USER_POOL_ID,
	ClientId: process.env.COGNITO_CLIENT_ID
};
const userPool = new AmazonCognitoIdentity.CognitoUserPool(poolData);
let cognitoUser;

function updateStatus(idToken) {
	fetch('https://5hc28j80m1.execute-api.sa-east-1.amazonaws.com/prod/valheim', {
		method: 'POST',
		headers: {
			'Content-Type': 'application/json',
			'Authorization': idToken
		},
		body: JSON.stringify({ action: 'status' })
	})
		.then(response => response.json())
		.then(data => {
			document.getElementById('currentStatus').innerText = `Status: ${data.status}`;
			if (data.public_ip && data.port) {
				document.getElementById('accessDetails').innerText = `Acesse o servidor: ${data.public_ip}:${data.port}`;
			}
			if (data.password) {
				document.getElementById('serverPassword').innerText = `Senha: ${data.password}`;
			}
			document.getElementById('result').style.display = 'block';
		})
		.catch(error => console.error('Error:', error));
}

function pollStatus(idToken, action) {
	const interval = setInterval(() => {
		fetch('https://5hc28j80m1.execute-api.sa-east-1.amazonaws.com/prod/valheim', {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
				'Authorization': idToken
			},
			body: JSON.stringify({ action: 'status' })
		})
			.then(response => response.json())
			.then(data => {
				if ((action === 'start' && data.status === 'ON') || (action === 'stop' && data.status === 'OFF')) {
					clearInterval(interval);
					updateStatus(idToken);
					document.getElementById('message').innerText = data.message;
				}
			})
			.catch(error => {
				clearInterval(interval);
				console.error('Error:', error);
			});
	}, 5000); // Poll every 5 seconds
}

document.getElementById('loginForm').addEventListener('submit', function (event) {
	event.preventDefault();
	const username = document.getElementById('username').value;
	const password = document.getElementById('password').value;

	const authenticationData = {
		Username: username,
		Password: password
	};
	const authenticationDetails = new AmazonCognitoIdentity.AuthenticationDetails(authenticationData);

	const userData = {
		Username: username,
		Pool: userPool
	};
	cognitoUser = new AmazonCognitoIdentity.CognitoUser(userData);

	cognitoUser.authenticateUser(authenticationDetails, {
		onSuccess: function (result) {
			const idToken = result.getIdToken().getJwtToken();
			document.getElementById('loginForm').style.display = 'none';
			document.getElementById('controlForm').style.display = 'block';

			updateStatus(idToken);

			document.getElementById('controlForm').addEventListener('submit', function (event) {
				event.preventDefault();
				const action = document.getElementById('action').value;

				fetch('https://5hc28j80m1.execute-api.sa-east-1.amazonaws.com/prod/valheim', {
					method: 'POST',
					headers: {
						'Content-Type': 'application/json',
						'Authorization': idToken
					},
					body: JSON.stringify({ action: action })
				})
					.then(response => response.json())
					.then(data => {
						document.getElementById('message').innerText = data.message;
						if (data.public_ip && data.port) {
							document.getElementById('accessDetails').innerText = `Acesse o servidor: ${data.public_ip}:${data.port}`;
						}
						if (data.password) {
							document.getElementById('serverPassword').innerText = `Senha: ${data.password}`;
						}
						document.getElementById('result').style.display = 'block';
						pollStatus(idToken, action);
					})
					.catch(error => console.error('Error:', error));
			});
		},
		onFailure: function (err) {
			alert(err.message || JSON.stringify(err));
		},
		newPasswordRequired: function (userAttributes, requiredAttributes) {
			document.getElementById('loginForm').style.display = 'none';
			document.getElementById('newPasswordForm').style.display = 'block';

			document.getElementById('newPasswordForm').addEventListener('submit', function (event) {
				event.preventDefault();
				const newPassword = document.getElementById('newPassword').value;
				cognitoUser.completeNewPasswordChallenge(newPassword, {}, {
					onSuccess: function (result) {
						const idToken = result.getIdToken().getJwtToken();
						document.getElementById('newPasswordForm').style.display = 'none';
						document.getElementById('controlForm').style.display = 'block';
						updateStatus(idToken);

						document.getElementById('controlForm').addEventListener('submit', function (event) {
							event.preventDefault();
							const action = document.getElementById('action').value;

							fetch('https://5hc28j80m1.execute-api.sa-east-1.amazonaws.com/prod/valheim', {
								method: 'POST',
								headers: {
									'Content-Type': 'application/json',
									'Authorization': idToken
								},
								body: JSON.stringify({ action: action })
							})
								.then(response => response.json())
								.then(data => {
									document.getElementById('message').innerText = data.message;
									if (data.public_ip && data.port) {
										document.getElementById('accessDetails').innerText = `Acesse o servidor: ${data.public_ip}:${data.port}`;
									}
									if (data.password) {
										document.getElementById('serverPassword').innerText = `Senha: ${data.password}`;
									}
									document.getElementById('result').style.display = 'block';
									pollStatus(idToken, action);
								})
								.catch(error => console.error('Error:', error));
						});
					},
					onFailure: function (err) {
						alert(err.message || JSON.stringify(err));
					}
				});
			});
		}
	});
});