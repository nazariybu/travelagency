package org.project.configuration;

import org.springframework.session.web.context.AbstractHttpSessionApplicationInitializer;

// Adds the springSessionRepositoryFilter before Spring Security,
// so Security reads the login from the Redis session.
public class SessionInitializer extends AbstractHttpSessionApplicationInitializer {
}
