package com.adam.striot;

import org.apache.activemq.ActiveMQConnectionFactory;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.jms.*;
import java.util.concurrent.LinkedBlockingQueue;


/**
 * Created by Adam Cattermole on 01/06/2018.
 */
public class AMQProducer implements Runnable {

    private final static Logger logger = LoggerFactory.getLogger(AMQProducer.class);

    private String host;
    private LinkedBlockingQueue<String> buffer;


    public AMQProducer(String host, LinkedBlockingQueue<String> buffer) {
        this.host = host;
        this.buffer = buffer;
    }

    public void run() {
        while (true) {
            try {
                produce();
            } catch (Exception e) {
                logger.error("Exception {} caught, restarting connection...", e.getClass().getCanonicalName());

            }
        }
    }

    public void produce() throws Exception {
        Connection connection = null;
        try {
            ConnectionFactory connectionFactory = new ActiveMQConnectionFactory("admin", "yy^U#Fca!52Y", String.format("tcp://%s:61616", this.host));
            //?jms.prefetchPolicy.queuePrefetch=25000

            connection = connectionFactory.createConnection();

            Session session = connection.createSession(false, Session.DUPS_OK_ACKNOWLEDGE);

            Queue destination = session.createQueue("SampleQueue");
            MessageProducer producer = session.createProducer(destination);
            producer.setDisableMessageID(true);
            producer.setDisableMessageTimestamp(true);
            producer.setDeliveryMode(DeliveryMode.NON_PERSISTENT);
            connection.start();

            logger.info("Connected to broker...");

            while (true) {
                String out = this.buffer.take();
                producer.send(session.createTextMessage(out));
            }
        } finally {
            if (connection != null) {
                connection.close();
            }

        }
    }

}
