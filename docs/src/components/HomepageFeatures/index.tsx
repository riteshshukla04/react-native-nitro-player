import type { ReactNode } from 'react';
import clsx from 'clsx';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type FeatureItem = {
  title: string;
  image: string;
  description: ReactNode;
};

const FeatureList: FeatureItem[] = [
  {
    title: 'High Performance',
    image: require('@site/static/img/feature_performance.png').default,
    description: (
      <>
        Built with <b>Nitro Modules</b> for zero-overhead native communication.
        Experience blazing fast performance on both iOS and Android.
      </>
    ),
  },
  {
    title: 'Feature Rich',
    image: require('@site/static/img/feature_rich.png').default,
    description: (
      <>
        Comes with playlist management, offline downloads, 5-band equalizer,
        background playback, and lock screen controls out of the box.
      </>
    ),
  },
  {
    title: 'Native Integration',
    image: require('@site/static/img/feature_native.png').default,
    description: (
      <>
        First-class support for <b>Android Auto</b> and <b>CarPlay</b>.
        Seamlessly integrates with native audio sessions and command centers.
      </>
    ),
  },
];

function Feature({ title, image, description }: FeatureItem) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center">
        <img src={image} className={styles.featureSvg} role="img" />
      </div>
      <div className="text--center padding-horiz--md">
        <Heading as="h3">{title}</Heading>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures(): ReactNode {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
