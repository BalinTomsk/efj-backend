package com.fishfind.docapi.status;

import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** Wires the request recorder that feeds {@link ServiceActivity}. */
@Configuration(proxyBeanMethods = false)
public class ServiceStatusConfig {

    @Bean
    public FilterRegistrationBean<ServiceActivityFilter> serviceActivityFilter(ServiceActivity activity) {
        FilterRegistrationBean<ServiceActivityFilter> registration =
                new FilterRegistrationBean<>(new ServiceActivityFilter(activity));
        registration.addUrlPatterns("/api/*");
        return registration;
    }
}
